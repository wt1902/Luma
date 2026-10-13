import Foundation
import Combine
import CommonCrypto
import CryptoKit
import os
@preconcurrency import Martin
import MartinOMEMO

extension XmppModuleIdentifier {
    static var omemo2: XmppModuleIdentifier<LumaOMEMO2Module> {
        LumaOMEMO2Module.IDENTIFIER
    }
}

/// OMEMO 2 (XEP-0384 0.8.3, urn:xmpp:omemo:2) support built on the
/// MartinOMEMO signal stack. Wire format implemented here:
/// - payload: AES-256-CBC + HMAC-SHA-256 keyed via HKDF ("OMEMO Payload"),
///   plaintext is a Stanza Content Encryption `<envelope>` (XEP-0420);
/// - header: `<keys jid>` groups with `<key rid kex>` elements;
/// - device list node `urn:xmpp:omemo:2:devices` (`<devices>` element);
/// - bundle node `urn:xmpp:omemo:2:bundles` (one item per device id,
///   `<bundle>` with `<spk>/<spks>/<ik>/<prekeys><pk>`).
/// The Double Ratchet sessions are shared with the legacy OMEMO module
/// through the same SignalStorage.
final class LumaOMEMO2Module: AbstractPEPModule, XmppModule, @unchecked Sendable {
    public static let ID = "omemo2"
    public static let IDENTIFIER = XmppModuleIdentifier<LumaOMEMO2Module>()
    public static let XMLNS = "urn:xmpp:omemo:2"
    public static let DEVICES_LIST_NODE = "urn:xmpp:omemo:2:devices"
    public static let BUNDLES_NODE = "urn:xmpp:omemo:2:bundles"
    public static let SCE_XMLNS = "urn:xmpp:sce:0"
    public static let HKDF_INFO = "OMEMO Payload"

    public let id: String = ID
    public let criteria = Criteria.empty()
    public let features: [String] = [LumaOMEMO2Module.DEVICES_LIST_NODE + "+notify"]

    public let signalContext: SignalContext
    public let storage: SignalStorage
    private let devicesQueue = DispatchQueue(label: "app.luma.omemo2.devices")
    private var devices: [BareJID: [Int32]] = [:]
    private var devicesFetchError: [BareJID: [Int32]] = [:]

    /// True once our device id has been published to the OMEMO 2 device
    /// list and our bundle is on the server. Drives the UI readiness flag.
    @Published public private(set) var isReady: Bool = false

    public override var isPepAvailable: Bool {
        didSet {
            if isPepAvailable {
                publishBundleIfNeeded { [weak self] in
                    self?.publishDeviceListIfNeeded()
                }
            }
        }
    }

    public init(signalContext: SignalContext, signalStorage: SignalStorage) {
        self.signalContext = signalContext
        self.storage = signalStorage
        super.init()
    }

    public func process(stanza: Stanza) throws {
        // Decryption is driven explicitly by XMPPService decode calls;
        // PEP notifications arrive through onItemNotification.
    }

    // MARK: - Device list

    public func devices(for jid: BareJID) -> [Int32]? {
        let known = devicesQueue.sync { devices[jid] }
        guard let known else { return nil }
        guard let failed = devicesFetchError[jid] else { return known }
        return known.filter { !failed.contains($0) }
    }

    /// Returns the cached OMEMO 2 device list for `jid`, fetching it from
    /// PEP on demand when `fetching` is true and nothing is cached yet. Used
    /// by the send path so the first message to an OMEMO 2-only contact does
    /// not fall back to the legacy protocol.
    public func deviceIDs(for jid: BareJID, fetching: Bool) async -> [Int32]? {
        if let known = devices(for: jid) { return known }
        guard fetching, let context else { return nil }
        return await withCheckedContinuation { continuation in
            context.module(.pubsub).retrieveItems(
                from: jid,
                for: Self.DEVICES_LIST_NODE,
                limit: .lastItems(1)
            ) { [weak self] result in
                guard let self,
                    case .success(let items) = result,
                    let listEl = items.items.first?.payload,
                    listEl.name == "devices",
                    listEl.xmlns == Self.XMLNS
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let known = listEl.mapChildren(transform: { $0.getAttribute("id").flatMap(Int32.init) })
                let jidString = jid.stringValue
                self.devicesQueue.async { self.devices[BareJID(jidString)] = known }
                continuation.resume(returning: known)
            }
        }
    }

    public func isAvailable(for jid: BareJID) -> Bool {
        !(devicesQueue.sync { devices[jid] }?.isEmpty ?? true)
            || !storage.sessionStore.allDevices(for: jid.stringValue, activeAndTrusted: true).isEmpty
    }

    private func publishDeviceListIfNeeded() {
        guard isPepAvailable, let context else { return }
        let pepJid = context.userBareJid
        context.module(.pubsub).retrieveItems(
            from: pepJid,
            for: Self.DEVICES_LIST_NODE,
            limit: .lastItems(1)
        ) { [weak self] result in
            switch result {
            case .success(let items):
                self?.processDeviceList(jid: pepJid, payload: items.items.first?.payload)
            case .failure(let error):
                guard error.error == .item_not_found || error.error == .internal_server_error() else { return }
                self?.processDeviceList(jid: pepJid, payload: nil)
            }
        }
    }

    private func processDeviceList(jid: BareJID, payload input: Element?) {
        guard let context else { return }
        var list = input
        if list?.name != "devices" || list?.xmlns != Self.XMLNS {
            list = Element(name: "devices", xmlns: Self.XMLNS)
        }
        guard let list else { return }

        let isOwn = jid == context.userBareJid
        let ourID = String(storage.identityKeyStore.localRegistrationId())
        var changed = false
        if isOwn,
            list.findChild(where: { $0.name == "device" && $0.getAttribute("id") == ourID }) == nil
        {
            list.addChild(Element(name: "device", attributes: ["id": ourID, "label": "Luma"]))
            changed = true
        }

        if isOwn, changed {
            let options = PubSubNodeConfig()
            options.accessModel = .open
            context.module(.pubsub).publishItem(
                at: jid,
                to: Self.DEVICES_LIST_NODE,
                itemId: "current",
                payload: list,
                publishOptions: options
            ) { [weak self] result in
                switch result {
                case .success:
                    Logger(subsystem: "Luma", category: "omemo2")
                        .info("device list published jid=\(jid.stringValue)")
                    self?.isReady = true
                case .failure(let error):
                    Logger(subsystem: "Luma", category: "omemo2")
                        .warning("device list publish failed: \(error.error)")
                    guard error.error == .conflict() else { return }
                    context.module(.pubsub).retrieveNodeConfiguration(
                        from: jid,
                        node: Self.DEVICES_LIST_NODE
                    ) { result in
                        guard case .success(let form) = result else { return }
                        form.accessModel = .open
                        context.module(.pubsub).configureNode(
                            at: jid,
                            node: Self.DEVICES_LIST_NODE,
                            with: form
                        ) { _ in
                            context.module(.pubsub).publishItem(
                                at: jid,
                                to: Self.DEVICES_LIST_NODE,
                                itemId: "current",
                                payload: list,
                                publishOptions: options
                            ) { result in
                                if case .success = result { self?.isReady = true }
                            }
                        }
                    }
                }
            }
        } else if isOwn {
            isReady = true
        }

        // Track known devices and align identity states with the list.
        let known = list.mapChildren(transform: { $0.getAttribute("id").flatMap(Int32.init) })
        devicesQueue.async { [weak self] in self?.devices[jid] = known }
        // Record which device IDs are OMEMO 2 so the encryption screen can
        // badge them; legacy-only identities stay unmarked.
        (storage as? LumaOMEMOStore)?.setOMEMO2DeviceIDs(Set(known), for: jid.stringValue)
        let active = storage.sessionStore.allDevices(for: jid.stringValue, activeAndTrusted: true)
        active.filter { !known.contains($0) }.forEach {
            _ = storage.identityKeyStore.setStatus(active: false, forIdentity: SignalAddress(name: jid.stringValue, deviceId: $0))
        }
        known.filter { !active.contains($0) }.forEach {
            _ = storage.identityKeyStore.setStatus(active: true, forIdentity: SignalAddress(name: jid.stringValue, deviceId: $0))
        }
    }

    override func onItemNotification(notification: PubSubModule.ItemNotification) {
        guard notification.node == Self.DEVICES_LIST_NODE, let context else { return }
        switch notification.action {
        case .published(let item):
            let from = notification.message.from?.bareJid ?? context.userBareJid
            processDeviceList(jid: from, payload: item.payload)
        default:
            break
        }
    }

    // MARK: - Bundle

    func publishBundleIfNeeded(completionHandler: (() -> Void)?) {
        guard isPepAvailable, let context else {
            completionHandler?()
            return
        }
        let deviceID = String(storage.identityKeyStore.localRegistrationId())
        context.module(.pubsub).retrieveItems(
            from: context.userBareJid,
            for: Self.BUNDLES_NODE,
            limit: .items(withIds: [deviceID])
        ) { [weak self] result in
            switch result {
            case .success(let items):
                self?.publishBundle(current: items.items.first?.payload, completionHandler: completionHandler)
            case .failure(let error):
                guard error.error == .item_not_found || error.error == .internal_server_error() else {
                    completionHandler?()
                    return
                }
                self?.publishBundle(current: nil, completionHandler: completionHandler)
            }
        }
    }

    private func signedPreKey(regenerate: Bool = false) -> SignalSignedPreKey? {
        let signedPreKeyId = storage.signedPreKeyStore.countSignedPreKeys()
        var signedPreKey: SignalSignedPreKey?
        if !regenerate, signedPreKeyId != 0,
            let data = signalContext.storage.signedPreKeyStore.loadSignedPreKey(withId: UInt32(signedPreKeyId))
        {
            signedPreKey = SignalSignedPreKey(fromSerializedData: data)
        }
        if signedPreKey == nil {
            guard let identityKeyPair = storage.identityKeyStore.keyPair() else { return nil }
            signedPreKey = signalContext.generateSignedPreKey(
                withIdentity: identityKeyPair,
                signedPreKeyId: UInt32(signedPreKeyId + 1)
            )
            guard let signedPreKey, let serialized = signedPreKey.serializedData else { return nil }
            guard signalContext.storage.signedPreKeyStore.storeSignedPreKey(serialized, withId: signedPreKey.preKeyId) else {
                return nil
            }
        }
        return signedPreKey
    }

    private func publishBundle(current input: Element?, completionHandler: (() -> Void)?) {
        guard let identityKeyPair = storage.identityKeyStore.keyPair(),
            let identityPublicKey = identityKeyPair.publicKey
        else {
            completionHandler?()
            return
        }

        var flush = input == nil
        if !flush {
            flush = identityPublicKey.base64EncodedString() != input?.findChild(name: "ik")?.value
        }

        guard let signedPreKey = signedPreKey(regenerate: flush) else {
            completionHandler?()
            return
        }
        let signedPublicBase64 = signedPreKey.publicKeyData?.base64EncodedString() ?? ""
        let signatureBase64 = signedPreKey.signature.base64EncodedString()
        var changed = flush
            || signedPublicBase64 != input?.findChild(name: "spk")?.value
            || signatureBase64 != input?.findChild(name: "spks")?.value

        let currentIDs = input?.findChild(name: "prekeys")?.mapChildren(transform: {
            $0.getAttribute("id").flatMap(UInt32.init)
        }) ?? []
        var validKeys = currentIDs.compactMap { id -> SignalPreKey? in
            guard let data = storage.preKeyStore.loadPreKey(withId: id) else { return nil }
            return SignalPreKey(fromSerializedData: data)
        }
        let needKeys = 100 - validKeys.count
        if needKeys > 0 {
            changed = true
            let start = storage.preKeyStore.currentPreKeyId() + 1
            let newKeys = signalContext.generatePreKeys(withStartingPreKeyId: start, count: UInt32(needKeys))
            validKeys += newKeys.filter { key in
                guard let serialized = key.serializedData else { return false }
                return storage.preKeyStore.storePreKey(serialized, withId: key.preKeyId)
            }
        }

        if changed {
            publishBundle(
                signedPreKey: signedPreKey,
                identityKey: identityPublicKey,
                preKeys: validKeys,
                completionHandler: completionHandler
            )
        } else {
            completionHandler?()
        }
    }

    private func publishBundle(
        signedPreKey: SignalSignedPreKey,
        identityKey: Data,
        preKeys: [SignalPreKey],
        completionHandler: (() -> Void)?
    ) {
        guard let context, let signedPreKeyPublic = signedPreKey.publicKeyData else {
            completionHandler?()
            return
        }

        let bundleEl = Element(name: "bundle", xmlns: Self.XMLNS)
        bundleEl.addChild(Element(
            name: "spk",
            cdata: signedPreKeyPublic.base64EncodedString(),
            attributes: ["id": String(signedPreKey.preKeyId)]
        ))
        bundleEl.addChild(Element(name: "spks", cdata: signedPreKey.signature.base64EncodedString()))
        bundleEl.addChild(Element(name: "ik", cdata: identityKey.base64EncodedString()))
        let pkElements = preKeys.map { preKey -> Element in
            let publicData = preKey.serializedPublicKey?.base64EncodedString() ?? ""
            return Element(name: "pk", cdata: publicData, attributes: ["id": String(preKey.preKeyId)])
        }
        bundleEl.addChild(Element(name: "prekeys", children: pkElements))

        let options = PubSubNodeConfig()
        options.accessModel = .open
        options.maxItems = .max

        let deviceID = String(storage.identityKeyStore.localRegistrationId())
        context.module(.pubsub).publishItem(
            at: nil,
            to: Self.BUNDLES_NODE,
            itemId: deviceID,
            payload: bundleEl,
            publishOptions: options
        ) { result in
            switch result {
            case .success:
                Logger(subsystem: "Luma", category: "omemo2")
                    .info("bundle published deviceID=\(deviceID)")
            case .failure(let error):
                Logger(subsystem: "Luma", category: "omemo2")
                    .warning("bundle publish failed: \(error.error)")
            }
            completionHandler?()
        }
    }

    // MARK: - Session building

    func buildSession(forAddress address: SignalAddress, completionHandler: (() -> Void)? = nil) {
        guard let context else {
            completionHandler?()
            return
        }
        let pepJid = BareJID(address.name)
        context.module(.pubsub).retrieveItems(
            from: pepJid,
            for: Self.BUNDLES_NODE,
            limit: .items(withIds: [String(address.deviceId)])
        ) { [weak self] result in
            defer { completionHandler?() }
            guard let self, case .success(let items) = result,
                let bundle = OMEMO2Bundle(from: items.items.first?.payload)
            else {
                self?.markDeviceAsFailed(for: pepJid, andDeviceId: address.deviceId)
                return
            }
            guard let preKey = bundle.preKeys.randomElement(),
                let preKeyBundle = SignalPreKeyBundle(
                    registrationId: 0,
                    deviceId: address.deviceId,
                    preKeyId: preKey.id,
                    preKeyPublic: preKey.data,
                    signedPreKeyId: bundle.signedPreKeyId,
                    signedPreKeyPublic: bundle.signedPreKeyPublic,
                    signedPreKeySignature: bundle.signedPreKeySignature,
                    identityKey: bundle.identityKey
                ),
                let builder = SignalSessionBuilder(withAddress: address, andContext: self.signalContext)
            else {
                self.markDeviceAsFailed(for: pepJid, andDeviceId: address.deviceId)
                return
            }
            _ = builder.processPreKeyBundle(bundle: preKeyBundle)
        }
    }

    private func markDeviceAsFailed(for jid: BareJID, andDeviceId deviceId: Int32) {
        var failed = devicesFetchError[jid] ?? []
        if !failed.contains(deviceId) {
            failed.append(deviceId)
            devicesFetchError[jid] = failed
        }
    }

    // MARK: - Decode

    public func decode(message: Message, from: BareJID, serverMsgId: String? = nil) -> DecryptionResult<Message, SignalError> {
        guard context != nil else { return .failure(.unknown) }
        guard let encryptedEl = message.firstChild(name: "encrypted", xmlns: Self.XMLNS),
            let headerEl = encryptedEl.findChild(name: "header"),
            let sid = UInt32(headerEl.getAttribute("sid") ?? "")
        else {
            return .failure(.notEncrypted)
        }

        let localDeviceID = String(storage.identityKeyStore.localRegistrationId())
        let ownJID = context!.userBareJid.stringValue.lowercased()

        // Collect candidate keys for our device: prefer the 0.8.3
        // `<keys jid>` grouping, fall back to direct `<key>` children.
        var keyElements: [Element] = []
        for keysEl in headerEl.getChildren(where: { $0.name == "keys" }) {
            guard keysEl.getAttribute("jid")?.lowercased() == ownJID else { continue }
            keyElements.append(contentsOf: keysEl.getChildren(where: { $0.name == "key" }))
        }
        if keyElements.isEmpty {
            keyElements = headerEl.getChildren(where: { $0.name == "key" })
        }
        let ours = keyElements.filter { $0.getAttribute("rid") == localDeviceID }
        guard !ours.isEmpty else {
            Logger(subsystem: "Luma", category: "omemo2")
                .warning("message not encrypted for us: from=\(from.stringValue) sid=\(sid) ourRid=\(localDeviceID) keyCount=\(keyElements.count) hasPayload=\(encryptedEl.findChild(name: "payload") != nil)")
            guard context!.userBareJid != from || sid != storage.identityKeyStore.localRegistrationId() else {
                return .failure(.duplicateMessage)
            }
            guard encryptedEl.findChild(name: "payload") != nil else {
                return .failure(.duplicateMessage)
            }
            return .failure(.invalidMessage)
        }

        let address = SignalAddress(name: from.stringValue, deviceId: Int32(bitPattern: sid))
        var lastError: SignalError = .unknown
        for keyEl in ours {
            guard let base64 = keyEl.value, let keyData = Data(base64Encoded: base64),
                let cipher = SignalSessionCipher(withAddress: address, andContext: signalContext)
            else {
                Logger(subsystem: "Luma", category: "omemo2")
                    .warning("unusable key element from=\(from.stringValue) sid=\(sid)")
                continue
            }
            let kexRaw = keyEl.getAttribute("kex") ?? ""
            let isKex = kexRaw == "true" || kexRaw == "1"
                || keyEl.getAttribute("prekey") == "true" || keyEl.getAttribute("prekey") == "1"
            // Trust the kex attribute first; some clients mislabel the key
            // element, so retry with the opposite interpretation before
            // giving up on the message.
            var elementError: SignalError = .unknown
            for prekey in [isKex, !isKex] {
                let result = cipher.decrypt(key: SignalSessionCipher.Key(
                    key: keyData,
                    deviceId: Int32(bitPattern: sid),
                    prekey: prekey
                ))
                switch result {
                case .success(let combined):
                    Logger(subsystem: "Luma", category: "omemo2")
                        .info("key decrypted from=\(from.stringValue) sid=\(sid) prekey=\(prekey)")
                    return finishDecode(
                        message: message,
                        encryptedEl: encryptedEl,
                        combined: combined,
                        address: address,
                        isKex: prekey
                    )
                case .failure(let error):
                    elementError = error
                }
            }
            lastError = elementError
            Logger(subsystem: "Luma", category: "omemo2")
                .warning("key decrypt failed: error=\(elementError) from=\(from.stringValue) sid=\(sid) kexAttr=\(kexRaw)")
        }

        Logger(subsystem: "Luma", category: "omemo2")
            .warning("decode failed: error=\(lastError) from=\(from.stringValue) sid=\(sid)")
        if (lastError == .noSession || lastError == .invalidMessage), serverMsgId != nil {
            buildSession(forAddress: address)
        }
        return .failure(lastError)
    }

    private func finishDecode(
        message: Message,
        encryptedEl: Element,
        combined: Data,
        address: SignalAddress,
        isKex: Bool
    ) -> DecryptionResult<Message, SignalError> {
        message.removeChild(encryptedEl)

        // A consumed prekey must leave our published bundle.
        if isKex, storage.preKeyStore.flushDeletedPreKeys() {
            publishBundleIfNeeded(completionHandler: nil)
        }

        guard let payloadValue = encryptedEl.findChild(name: "payload")?.value,
            let ciphertext = Data(base64Encoded: payloadValue)
        else {
            // Empty message: session management, nothing to display.
            return .successTransportKey(combined, iv: Data())
        }

        // combined = key (32) || truncated HMAC (16)
        guard combined.count >= 48 else { return .failure(.invalidMac) }
        let key = combined.subdata(in: 0..<32)
        let expectedMAC = combined.subdata(in: 32..<48)
        guard let derived = Self.derivePayloadKeys(from: key) else { return .failure(.invalidMac) }
        let computedMAC = Data(HMAC<SHA256>.authenticationCode(
            for: ciphertext,
            using: SymmetricKey(data: derived.authKey)
        ).prefix(16))
        guard Self.constantTimeEquals(computedMAC, expectedMAC) else {
            Logger(subsystem: "Luma", category: "omemo2")
                .warning("payload HMAC mismatch from=\(address.name) device=\(address.deviceId)")
            return .failure(.invalidMac)
        }

        guard let plaintext = Self.aes256CBCDecrypt(ciphertext, key: derived.encryptionKey, iv: derived.iv),
            let plaintextString = String(data: plaintext, encoding: .utf8),
            let envelope = Element.from(string: plaintextString),
            envelope.name == "envelope"
        else {
            Logger(subsystem: "Luma", category: "omemo2")
                .warning("payload envelope parse failed from=\(address.name) device=\(address.deviceId)")
            return .failure(.invalidMessage)
        }

        if let content = envelope.findChild(name: "content"),
            let bodyEl = content.findChild(name: "body"),
            let body = bodyEl.value, !body.isEmpty
        {
            message.body = body
        }

        Logger(subsystem: "Luma", category: "omemo2")
            .info("decoded message from=\(address.name) device=\(address.deviceId) bodyLen=\(message.body?.count ?? 0)")
        _ = storage.identityKeyStore.setStatus(active: true, forIdentity: address)
        return .successMessage(
            message,
            fingerprint: storage.identityKeyStore.identityFingerprint(forAddress: address)
        )
    }

    // MARK: - Encode

    public func encode(
        message: Message,
        withStoreHint: Bool = true,
        completionHandler: @escaping (EncryptionResult<Message, SignalError>) -> Void
    ) {
        guard let jid = message.to?.bareJid else {
            completionHandler(.failure(.noDestination))
            return
        }
        encode(message: message, for: [jid], withStoreHint: withStoreHint, completionHandler: completionHandler)
    }

    public func addresses(
        for jids: [BareJID],
        completionHandler: @escaping (Result<[SignalAddress], SignalError>) -> Void
    ) {
        guard let pubsub = context?.module(.pubsub) else {
            completionHandler(.failure(.unknown))
            return
        }
        let group = DispatchGroup()
        var addresses: [SignalAddress] = []
        for jid in jids {
            if let known = devices(for: jid) {
                let knownAddresses = known.map { SignalAddress(name: jid.stringValue, deviceId: $0) }
                addresses.append(contentsOf: knownAddresses)
                for address in knownAddresses where !storage.sessionStore.containsSessionRecord(forAddress: address) {
                    group.enter()
                    buildSession(forAddress: address) { group.leave() }
                }
            } else {
                group.enter()
                pubsub.retrieveItems(from: jid, for: Self.DEVICES_LIST_NODE, limit: .lastItems(1)) { [weak self] result in
                    defer { group.leave() }
                    guard let self, case .success(let items) = result,
                        let listEl = items.items.first?.payload,
                        listEl.name == "devices", listEl.xmlns == Self.XMLNS
                    else { return }
                    let known = listEl.mapChildren(transform: { $0.getAttribute("id").flatMap(Int32.init) })
                    self.devicesQueue.async { self.devices[jid] = known }
                    let knownAddresses = known.map { SignalAddress(name: jid.stringValue, deviceId: $0) }
                    addresses.append(contentsOf: knownAddresses)
                    for address in knownAddresses where !self.storage.sessionStore.containsSessionRecord(forAddress: address) {
                        group.enter()
                        self.buildSession(forAddress: address) { group.leave() }
                    }
                }
            }
        }
        group.notify(queue: .main) {
            completionHandler(.success(addresses))
        }
    }

    public func encode(
        message: Message,
        for jids: [BareJID],
        withStoreHint: Bool = true,
        completionHandler: @escaping (EncryptionResult<Message, SignalError>) -> Void
    ) {
        addresses(for: jids) { result in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
            case .success(let addresses):
                if addresses.isEmpty {
                    completionHandler(.failure(.noSession))
                } else {
                    self.encode(message: message, forAddresses: addresses, withStoreHint: withStoreHint, completionHandler: completionHandler)
                }
            }
        }
    }

    public func encode(
        message: Message,
        forAddresses addresses: [SignalAddress],
        roomJID: BareJID? = nil,
        withStoreHint: Bool = true,
        completionHandler: @escaping (EncryptionResult<Message, SignalError>) -> Void
    ) {
        let result = encodeMessage(message: message, for: addresses, roomJID: roomJID)
        switch result {
        case .successMessage(let encoded, _):
            if withStoreHint {
                encoded.addChild(Element(name: "store", xmlns: "urn:xmpp:hints"))
            }
        default:
            break
        }
        completionHandler(result)
    }

    private func encodeMessage(
        message: Message,
        for remoteAddresses: [SignalAddress],
        roomJID: BareJID?
    ) -> EncryptionResult<Message, SignalError> {
        guard let context else { return .failure(.unknown) }

        let localAddresses = storage.sessionStore
            .allDevices(for: context.userBareJid.stringValue, activeAndTrusted: true)
            .map { SignalAddress(name: context.userBareJid.stringValue, deviceId: $0) }
        let destinations = Set(remoteAddresses + localAddresses)

        // Stanza Content Encryption envelope (XEP-0420) as the plaintext.
        let envelopeXML = Self.envelopeXML(
            body: message.body,
            from: context.userBareJid.stringValue,
            to: roomJID?.stringValue
        )
        guard let plaintext = envelopeXML.data(using: .utf8) else { return .failure(.unknown) }

        var key = Data(count: 32)
        key.withUnsafeMutableBytes { bytes in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard let derived = Self.derivePayloadKeys(from: key) else { return .failure(.unknown) }
        guard let ciphertext = Self.aes256CBCEncrypt(plaintext, key: derived.encryptionKey, iv: derived.iv) else {
            return .failure(.unknown)
        }
        let mac = Data(HMAC<SHA256>.authenticationCode(
            for: ciphertext,
            using: SymmetricKey(data: derived.authKey)
        ).prefix(16))
        var combinedKey = key
        combinedKey.append(mac)

        let encryptedEl = Element(name: "encrypted", xmlns: Self.XMLNS)
        let header = Element(name: "header")
        header.setAttribute("sid", value: String(storage.identityKeyStore.localRegistrationId()))
        encryptedEl.addChild(header)

        var keysByJID: [String: [Element]] = [:]
        for address in destinations {
            guard let cipher = SignalSessionCipher(withAddress: address, andContext: signalContext) else { continue }
            switch cipher.encrypt(data: combinedKey) {
            case .success(let output):
                let keyEl = Element(name: "key", cdata: output.key.base64EncodedString())
                keyEl.setAttribute("rid", value: String(output.deviceId))
                if output.prekey { keyEl.setAttribute("kex", value: "true") }
                keysByJID[address.name.lowercased(), default: []].append(keyEl)
            case .failure:
                break
            }
        }
        for (jid, keys) in keysByJID {
            let keysEl = Element(name: "keys")
            keysEl.setAttribute("jid", value: jid)
            keysEl.addChildren(keys)
            header.addChild(keysEl)
        }

        encryptedEl.addChild(Element(name: "payload", cdata: ciphertext.base64EncodedString()))
        message.body = nil
        message.addChild(encryptedEl)

        let fingerprint = storage.identityKeyStore.identityFingerprint(
            forAddress: SignalAddress(
                name: context.userBareJid.stringValue,
                deviceId: Int32(bitPattern: storage.identityKeyStore.localRegistrationId())
            )
        )
        return .successMessage(message, fingerprint: fingerprint)
    }

    // MARK: - Crypto helpers (internal for unit tests)

    struct PayloadKeys: Equatable {
        let encryptionKey: Data
        let authKey: Data
        let iv: Data
    }

    static func derivePayloadKeys(from key: Data) -> PayloadKeys? {
        guard key.count == 32 else { return nil }
        let salt = Data(count: 32) // 256 zero bits
        let material = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: key),
            salt: salt,
            info: Data(HKDF_INFO.utf8),
            outputByteCount: 80
        )
        let bytes = material.withUnsafeBytes { Data($0) }
        return PayloadKeys(
            encryptionKey: bytes.subdata(in: 0..<32),
            authKey: bytes.subdata(in: 32..<64),
            iv: bytes.subdata(in: 64..<80)
        )
    }

    static func aes256CBCEncrypt(_ plaintext: Data, key: Data, iv: Data) -> Data? {
        crypt(operation: CCOperation(kCCEncrypt), data: plaintext, key: key, iv: iv)
    }

    static func aes256CBCDecrypt(_ ciphertext: Data, key: Data, iv: Data) -> Data? {
        crypt(operation: CCOperation(kCCDecrypt), data: ciphertext, key: key, iv: iv)
    }

    private static func crypt(operation: CCOperation, data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else { return nil }
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var moved = 0
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    buffer.withUnsafeMutableBytes { outBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBytes.baseAddress, bufferSize,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        buffer.removeSubrange(moved..<buffer.count)
        return buffer
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    static func envelopeXML(body: String?, from fromJID: String, to toJID: String?) -> String {
        var content = ""
        if let body, !body.isEmpty {
            content += "<body xmlns='jabber:client'>" + escapeXML(body) + "</body>"
        }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let rpadLength = Int.random(in: 12...96)
        let rpad = String((0..<rpadLength).map { _ in alphabet.randomElement()! })
        var result = "<envelope xmlns='" + Self.SCE_XMLNS + "'><content>" + content + "</content>"
        result += "<rpad>" + rpad + "</rpad>"
        result += "<from jid='" + escapeXML(fromJID) + "'/>"
        if let toJID {
            result += "<to jid='" + escapeXML(toJID) + "'/>"
        }
        result += "</envelope>"
        return result
    }

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Parsed `urn:xmpp:omemo:2` bundle (`<spk>/<spks>/<ik>/<prekeys><pk>`).
struct OMEMO2Bundle {
    let signedPreKeyId: UInt32
    let signedPreKeyPublic: Data
    let signedPreKeySignature: Data
    let identityKey: Data
    let preKeys: [(id: UInt32, data: Data)]

    init?(from element: Element?) {
        guard let element,
            element.name == "bundle", element.xmlns == LumaOMEMO2Module.XMLNS,
            let spk = element.findChild(name: "spk"),
            let spkID = spk.getAttribute("id").flatMap(UInt32.init),
            let spkValue = spk.value,
            let spkData = Data(base64Encoded: spkValue),
            let spks = element.findChild(name: "spks")?.value,
            let spksData = Data(base64Encoded: spks),
            let ik = element.findChild(name: "ik")?.value,
            let ikData = Data(base64Encoded: ik),
            let preKeysEl = element.findChild(name: "prekeys")
        else { return nil }

        let parsedPreKeys = preKeysEl.mapChildren(transform: { pk -> (UInt32, Data)? in
            guard pk.name == "pk",
                let id = pk.getAttribute("id").flatMap(UInt32.init),
                let value = pk.value,
                let data = Data(base64Encoded: value)
            else { return nil }
            return (id, data)
        })
        guard !parsedPreKeys.isEmpty else { return nil }

        signedPreKeyId = spkID
        signedPreKeyPublic = spkData
        signedPreKeySignature = spksData
        identityKey = ikData
        preKeys = parsedPreKeys
    }
}

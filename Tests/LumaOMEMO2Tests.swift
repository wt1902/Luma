import XCTest
import Foundation
import CryptoKit
@testable import Luma
import Martin
import MartinOMEMO

final class LumaOMEMO2Tests: XCTestCase {

    // MARK: - Payload crypto (XEP-0384 0.8.3, section 4.4)

    func testDerivePayloadKeysHasStableStructure() throws {
        let key = Data(repeating: 0x42, count: 32)
        let derived = try XCTUnwrap(LumaOMEMO2Module.derivePayloadKeys(from: key))
        XCTAssertEqual(derived.encryptionKey.count, 32)
        XCTAssertEqual(derived.authKey.count, 32)
        XCTAssertEqual(derived.iv.count, 16)

        // Deterministic and key-dependent.
        XCTAssertEqual(derived, LumaOMEMO2Module.derivePayloadKeys(from: key))
        let other = try XCTUnwrap(LumaOMEMO2Module.derivePayloadKeys(from: Data(repeating: 0x43, count: 32)))
        XCTAssertNotEqual(derived, other)

        // Wrong input size is rejected.
        XCTAssertNil(LumaOMEMO2Module.derivePayloadKeys(from: Data([1, 2, 3])))
    }

    func testCBCRoundTrip() throws {
        let key = Data(repeating: 0x11, count: 32)
        let iv = Data(repeating: 0x22, count: 16)
        let plaintext = Data("OMEMO 2 payload".utf8)

        let ciphertext = try XCTUnwrap(LumaOMEMO2Module.aes256CBCEncrypt(plaintext, key: key, iv: iv))
        XCTAssertNotEqual(ciphertext, plaintext)
        let recovered = try XCTUnwrap(LumaOMEMO2Module.aes256CBCDecrypt(ciphertext, key: key, iv: iv))
        XCTAssertEqual(recovered, plaintext)

        // A wrong key never recovers the plaintext: the padding check may
        // either reject the result or yield garbage, but never the content.
        // Integrity itself is guaranteed by the HMAC step in finishDecode.
        let wrongKey = Data(repeating: 0x12, count: 32)
        let wrong = LumaOMEMO2Module.aes256CBCDecrypt(ciphertext, key: wrongKey, iv: iv)
        if let wrong {
            XCTAssertNotEqual(wrong, plaintext)
        }

        // PKCS#7 padding rounds up to a whole block.
        XCTAssertEqual(ciphertext.count % 16, 0)
    }

    func testHMACTruncationMatchesManualComputation() throws {
        let authKey = Data(repeating: 0x33, count: 32)
        let message = Data("authenticate me".utf8)
        let full = Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: authKey)))
        XCTAssertEqual(full.count, 32)
        // The wire format keeps the first 16 bytes ("cutting off excess
        // bytes from the end" in the spec).
        let truncated = Data(full.prefix(16))
        XCTAssertEqual(truncated.count, 16)
        XCTAssertEqual(LumaOMEMO2Module.constantTimeEquals(truncated, full.subdata(in: 0..<16)), true)
        XCTAssertFalse(LumaOMEMO2Module.constantTimeEquals(truncated, Data(repeating: 0, count: 16)))
        XCTAssertFalse(LumaOMEMO2Module.constantTimeEquals(truncated, Data([1])))
    }

    // MARK: - SCE envelope (XEP-0420)

    func testEnvelopeRoundTrip() throws {
        let xml = LumaOMEMO2Module.envelopeXML(
            body: "Привет & <тест>",
            from: "user@example.org",
            to: nil
        )
        let envelope = try XCTUnwrap(Element.from(string: xml))
        XCTAssertEqual(envelope.name, "envelope")
        XCTAssertEqual(envelope.xmlns, "urn:xmpp:sce:0")

        let content = try XCTUnwrap(envelope.findChild(name: "content"))
        let body = try XCTUnwrap(content.findChild(name: "body"))
        XCTAssertEqual(body.value, "Привет & <тест>")
        XCTAssertEqual(body.xmlns, "jabber:client")

        // rpad must be present and non-empty.
        let rpad = try XCTUnwrap(envelope.findChild(name: "rpad")?.value)
        XCTAssertFalse(rpad.isEmpty)

        // from affix is mandatory.
        XCTAssertEqual(envelope.findChild(name: "from")?.getAttribute("jid"), "user@example.org")
        // No <to> without a MUC.
        XCTAssertNil(envelope.findChild(name: "to"))
    }

    func testEnvelopeIncludesToAffixForMUC() throws {
        let xml = LumaOMEMO2Module.envelopeXML(
            body: "hi",
            from: "user@example.org",
            to: "room@conference.example.org"
        )
        let envelope = try XCTUnwrap(Element.from(string: xml))
        XCTAssertEqual(
            envelope.findChild(name: "to")?.getAttribute("jid"),
            "room@conference.example.org"
        )
    }

    func testSCEEnvelopeUsesSCE0Namespace() throws {
        // XEP-0420 Stanza Content Encryption uses urn:xmpp:sce:0; OMEMO 2
        // relies on that exact namespace for the encrypted payload envelope.
        XCTAssertEqual(LumaOMEMO2Module.SCE_XMLNS, "urn:xmpp:sce:0")
        let xml = LumaOMEMO2Module.envelopeXML(body: "hi", from: "a@b.c", to: nil)
        let envelope = try XCTUnwrap(Element.from(string: xml))
        XCTAssertEqual(envelope.name, "envelope")
        XCTAssertEqual(envelope.xmlns, "urn:xmpp:sce:0")
    }

    // MARK: - Bundle parsing

    func testBundleParsing() throws {
        let bundle = Element(name: "bundle", xmlns: "urn:xmpp:omemo:2")
        bundle.addChild(Element(name: "spk", cdata: Data([1, 2, 3]).base64EncodedString(), attributes: ["id": "7"]))
        bundle.addChild(Element(name: "spks", cdata: Data([4, 5, 6]).base64EncodedString()))
        bundle.addChild(Element(name: "ik", cdata: Data([7, 8, 9]).base64EncodedString()))
        let prekeys = Element(name: "prekeys")
        prekeys.addChild(Element(name: "pk", cdata: Data([10, 11]).base64EncodedString(), attributes: ["id": "11"]))
        prekeys.addChild(Element(name: "pk", cdata: Data([12, 13]).base64EncodedString(), attributes: ["id": "12"]))
        bundle.addChild(prekeys)

        let parsed = try XCTUnwrap(OMEMO2Bundle(from: bundle))
        XCTAssertEqual(parsed.signedPreKeyId, 7)
        XCTAssertEqual(parsed.signedPreKeyPublic, Data([1, 2, 3]))
        XCTAssertEqual(parsed.signedPreKeySignature, Data([4, 5, 6]))
        XCTAssertEqual(parsed.identityKey, Data([7, 8, 9]))
        XCTAssertEqual(parsed.preKeys.count, 2)

        // Wrong namespace is rejected.
        bundle.xmlns = "urn:xmpp:omemo:0"
        XCTAssertNil(OMEMO2Bundle(from: bundle))
    }

    // MARK: - OMEMODevice protocol label & store wiring

    func testOMEMODeviceProtocolLabel() {
        let legacy = OMEMODevice(
            jid: "bob@example.org",
            deviceID: 5,
            fingerprint: "aa",
            trust: .trusted,
            isActive: true,
            isOwn: false,
            isOMEMO2: false
        )
        let omemo2 = OMEMODevice(
            jid: "bob@example.org",
            deviceID: 5,
            fingerprint: "bb",
            trust: .trusted,
            isActive: true,
            isOwn: false,
            isOMEMO2: true
        )

        XCTAssertEqual(legacy.protocolName, "OMEMO")
        XCTAssertEqual(omemo2.protocolName, "OMEMO 2")
        // Same JID/deviceID across protocols must not collide as list rows.
        XCTAssertEqual(legacy.id, "bob@example.org|5|legacy")
        XCTAssertEqual(omemo2.id, "bob@example.org|5|omemo2")
        XCTAssertNotEqual(legacy.id, omemo2.id)
    }

    func testStoreMarksOMEMO2DeviceIDs() throws {
        let store = LumaOMEMOStore(accountJID: "alice@example.org")
        let context = try XCTUnwrap(SignalContext(withStorage: store))
        _ = context
        let ownID = store.localRegistrationID
        XCTAssertNotEqual(ownID, 0)

        store.setOMEMO2DeviceIDs([Int32(bitPattern: ownID)], for: "alice@example.org")
        let devices = store.devices(for: "alice@example.org")
        let own = try XCTUnwrap(devices.first { $0.isOwn })
        XCTAssertTrue(own.isOMEMO2)

        // Clearing the published set drops the badge.
        store.setOMEMO2DeviceIDs([], for: "alice@example.org")
        let cleared = store.devices(for: "alice@example.org")
        let clearedOwn = try XCTUnwrap(cleared.first { $0.isOwn })
        XCTAssertFalse(clearedOwn.isOMEMO2)
    }

    // MARK: - Double Ratchet round trip (shared with the legacy module)

    func testRatchetSessionRoundTrip() throws {
        let alice = try makeStorage()
        let bob = try makeStorage()

        let aliceContext = try XCTUnwrap(SignalContext(withStorage: alice))
        let bobContext = try XCTUnwrap(SignalContext(withStorage: bob))

        let aliceDevice = Int32(bitPattern: alice.identities.localRegistrationId())
        let aliceAddress = SignalAddress(name: "alice@example.org", deviceId: aliceDevice)
        let bobAddress = SignalAddress(name: "bob@example.org", deviceId: Int32(bitPattern: bob.identities.localRegistrationId()))

        // Bob builds a session with Alice from her published bundle.
        let preKey = try XCTUnwrap(alice.preKeys.loadPreKey(withId: 1))
        let preKeyRecord = try XCTUnwrap(SignalPreKey(fromSerializedData: preKey))
        let signedPreKey = try XCTUnwrap(alice.signedPreKeys.loadSignedPreKey(withId: 1))
        let signedPreKeyRecord = try XCTUnwrap(SignalSignedPreKey(fromSerializedData: signedPreKey))
        let identityKey = try XCTUnwrap(alice.identities.keyPair()?.publicKey)
        let bundle = try XCTUnwrap(SignalPreKeyBundle(
            registrationId: 0,
            deviceId: aliceDevice,
            preKeyId: 1,
            preKeyPublic: try XCTUnwrap(preKeyRecord.serializedPublicKey),
            signedPreKeyId: 1,
            signedPreKeyPublic: try XCTUnwrap(signedPreKeyRecord.publicKeyData),
            signedPreKeySignature: signedPreKeyRecord.signature,
            identityKey: identityKey
        ))
        let builder = try XCTUnwrap(SignalSessionBuilder(withAddress: aliceAddress, andContext: bobContext))
        XCTAssertTrue(builder.processPreKeyBundle(bundle: bundle))

        // The 48-byte combined key (payload key + truncated HMAC) travels
        // through the ratchet exactly like in LumaOMEMO2Module.
        var combined = Data(repeating: 0x5A, count: 32)
        combined.append(Data(repeating: 0x3C, count: 16))

        let bobCipher = try XCTUnwrap(SignalSessionCipher(withAddress: aliceAddress, andContext: bobContext))
        let encryptedKey = try bobCipher.encrypt(data: combined).get()
        XCTAssertTrue(encryptedKey.prekey)

        let aliceCipher = try XCTUnwrap(SignalSessionCipher(withAddress: bobAddress, andContext: aliceContext))
        let decrypted = try aliceCipher.decrypt(key: SignalSessionCipher.Key(
            key: encryptedKey.key,
            deviceId: Int32(bitPattern: bob.identities.localRegistrationId()),
            prekey: true
        )).get()
        XCTAssertEqual(decrypted, combined)
    }
}

// MARK: - In-memory signal stores

private final class TestOMEMOStorage: SignalStorage {
    let sessions = InMemorySessionStore()
    let preKeys = InMemoryPreKeyStore()
    let signedPreKeys = InMemorySignedPreKeyStore()
    let identities = InMemoryIdentityKeyStore()
    let senderKeys = InMemorySenderKeyStore()

    init() {
        super.init(
            sessionStore: sessions,
            preKeyStore: preKeys,
            signedPreKeyStore: signedPreKeys,
            identityKeyStore: identities,
            senderKeyStore: senderKeys
        )
    }

    override func setup(withContext context: SignalContext) {
        identities.registrationID = context.generateRegistrationId()
        if let pair = SignalIdentityKeyPair.generateKeyPair(context: context) {
            identities.keyPairData = pair.serialized()
        }
        if let identityKeyPair = identities.keyPair(),
            let signedPreKey = context.generateSignedPreKey(withIdentity: identityKeyPair, signedPreKeyId: 1),
            let serialized = signedPreKey.serializedData {
            _ = signedPreKeys.storeSignedPreKey(serialized, withId: 1)
        }
        let generated = context.generatePreKeys(withStartingPreKeyId: 1, count: 1)
        for preKey in generated {
            if let serialized = preKey.serializedData {
                _ = preKeys.storePreKey(serialized, withId: preKey.preKeyId)
            }
        }
        super.setup(withContext: context)
    }
}

private final class InMemorySessionStore: SignalSessionStoreProtocol {
    private var records: [String: Data] = [:]
    func sessionRecord(forAddress address: SignalAddress) -> Data? {
        records["\(address.name)|\(address.deviceId)"]
    }
    func allDevices(for name: String, activeAndTrusted: Bool) -> [Int32] { [] }
    func storeSessionRecord(_ data: Data, forAddress address: SignalAddress) -> Bool {
        records["\(address.name)|\(address.deviceId)"] = data
        return true
    }
    func containsSessionRecord(forAddress address: SignalAddress) -> Bool {
        sessionRecord(forAddress: address) != nil
    }
    func deleteSessionRecord(forAddress address: SignalAddress) -> Bool {
        records.removeValue(forKey: "\(address.name)|\(address.deviceId)") != nil
    }
    func deleteAllSessions(for name: String) -> Bool {
        records.removeAll()
        return true
    }
}

private final class InMemoryPreKeyStore: SignalPreKeyStoreProtocol {
    private var keys: [UInt32: Data] = [:]
    private var pendingDeletion: Set<UInt32> = []
    func currentPreKeyId() -> UInt32 { keys.keys.max() ?? 0 }
    func loadPreKey(withId id: UInt32) -> Data? { keys[id] }
    func storePreKey(_ data: Data, withId id: UInt32) -> Bool {
        keys[id] = data
        return true
    }
    func containsPreKey(withId id: UInt32) -> Bool { keys[id] != nil }
    func deletePreKey(withId id: UInt32) -> Bool {
        pendingDeletion.insert(id)
        return true
    }
    func flushDeletedPreKeys() -> Bool {
        let ids = pendingDeletion
        pendingDeletion.removeAll()
        ids.forEach { keys.removeValue(forKey: $0) }
        return !ids.isEmpty
    }
}

private final class InMemorySignedPreKeyStore: SignalSignedPreKeyStoreProtocol {
    private var keys: [UInt32: Data] = [:]
    func countSignedPreKeys() -> Int { keys.count }
    func loadSignedPreKey(withId id: UInt32) -> Data? { keys[id] }
    func storeSignedPreKey(_ data: Data, withId id: UInt32) -> Bool {
        keys[id] = data
        return true
    }
    func containsSignedPreKey(withId id: UInt32) -> Bool { keys[id] != nil }
    func deleteSignedPreKey(withId id: UInt32) -> Bool {
        keys.removeValue(forKey: id) != nil
    }
}

private final class InMemoryIdentityKeyStore: SignalIdentityKeyStoreProtocol {
    var registrationID: UInt32 = 0
    var keyPairData: Data?
    private var identities: [String: Data] = [:]
    func keyPair() -> SignalIdentityKeyPairProtocol? {
        guard let keyPairData else { return nil }
        return SignalIdentityKeyPair(fromKeyPairData: keyPairData)
    }
    func localRegistrationId() -> UInt32 { registrationID }
    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        save(identity: identity, publicKeyData: key?.publicKey)
    }
    func isTrusted(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        isTrusted(identity: identity, publicKeyData: key?.publicKey)
    }
    func save(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        guard let publicKeyData else { return false }
        identities["\(identity.name)|\(identity.deviceId)"] = publicKeyData
        return true
    }
    func isTrusted(identity: SignalAddress, publicKeyData: Data?) -> Bool { true }
    func setStatus(_ status: IdentityStatus, forIdentity identity: SignalAddress) -> Bool { true }
    func setStatus(active: Bool, forIdentity identity: SignalAddress) -> Bool { true }
    func identities(forName name: String) -> [Identity] { [] }
    func identityFingerprint(forAddress address: SignalAddress) -> String? { nil }
}

private final class InMemorySenderKeyStore: SignalSenderKeyStoreProtocol {
    private var keys: [String: Data] = [:]
    func storeSenderKey(_ key: Data, address: SignalAddress?, groupId: String?) -> Bool {
        keys["\(address?.name ?? "-")|\(groupId ?? "-")"] = key
        return true
    }
    func loadSenderKey(forAddress address: SignalAddress?, groupId: String?) -> Data? {
        keys["\(address?.name ?? "-")|\(groupId ?? "-")"]
    }
}

private func makeStorage() throws -> TestOMEMOStorage {
    TestOMEMOStorage()
}

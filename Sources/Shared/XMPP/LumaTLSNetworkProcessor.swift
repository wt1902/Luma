import CryptoKit
import Foundation
import Martin
import OpenSSL
import Security

/// Negotiated TLS parameters of the live connection, captured by the TLS
/// processor and shared with the SASL layer (SCRAM channel binding) and the
/// server-information screen.
struct LumaTLSState: Sendable {
    /// "TLSv1.3" / "TLSv1.2" — OpenSSL's SSL_get_version string.
    let version: String
    /// OpenSSL cipher-suite name, e.g. TLS_AES_256_GCM_SHA384.
    let cipher: String
    /// DER of the leaf certificate.
    let leafCertificateDER: Data
    /// RFC 9266 tls-exporter output (32 bytes), when the handshake version
    /// supports exporters (TLS 1.3).
    let exporter: Data?
}

/// Thread-safe holder of the negotiated TLS state plus the channel-binding
/// types the server advertised in its stream features.
final class LumaChannelBindingStore: @unchecked Sendable {
    private let lock = NSLock()
    private var tlsState: LumaTLSState?
    private var advertisedTypes: Set<String> = []
    /// Ordered copies of the advertised SASL mechanism and channel-binding
    /// lists — XEP-0474 hashes them in advertisement order.
    private var mechanismsOrdered: [String] = []
    private var channelBindingTypesOrdered: [String] = []
    private var downgradeProtectionDetected = false

    func setTLSState(_ state: LumaTLSState) {
        lock.lock()
        tlsState = state
        lock.unlock()
    }

    func setAdvertisedChannelBindingTypes(_ types: Set<String>) {
        lock.lock()
        advertisedTypes = types
        lock.unlock()
    }

    /// Records the advertised lists for the XEP-0474 downgrade-protection
    /// hash and the server-information screen.
    func setSASLContext(
        mechanisms: [String],
        channelBindingTypes: [String]
    ) {
        lock.lock()
        mechanismsOrdered = mechanisms
        channelBindingTypesOrdered = channelBindingTypes
        lock.unlock()
    }

    func markDowngradeProtectionDetected() {
        lock.lock()
        downgradeProtectionDetected = true
        lock.unlock()
    }

    var isDowngradeProtectionDetected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return downgradeProtectionDetected
    }

    var advertisedSASLMechanismsOrdered: [String] {
        lock.lock()
        defer { lock.unlock() }
        return mechanismsOrdered
    }

    var advertisedChannelBindingTypesOrdered: [String] {
        lock.lock()
        defer { lock.unlock() }
        return channelBindingTypesOrdered
    }

    func reset() {
        lock.lock()
        tlsState = nil
        advertisedTypes = []
        mechanismsOrdered = []
        channelBindingTypesOrdered = []
        downgradeProtectionDetected = false
        lock.unlock()
    }

    var negotiatedState: LumaTLSState? {
        lock.lock()
        defer { lock.unlock() }
        return tlsState
    }

    /// The strongest channel-binding type both sides support: RFC 9266
    /// tls-exporter first, then tls-server-end-point.
    var preferredChannelBindingType: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let tlsState else { return nil }
        if advertisedTypes.contains("tls-exporter"), tlsState.exporter != nil {
            return "tls-exporter"
        }
        if advertisedTypes.contains("tls-server-end-point") {
            return "tls-server-end-point"
        }
        return nil
    }

    /// Channel-binding data for a concrete type: RFC 9266 §4.2 for
    /// tls-exporter and §4.3 for tls-server-end-point (SHA-256 of the leaf
    /// certificate; RFC 5929's upgrade rules make this correct for the
    /// SHA-256-signed certificates used in practice on TLS 1.2 as well).
    func channelBindingData(for type: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let tlsState else { return nil }
        switch type {
        case "tls-exporter":
            return tlsState.exporter
        case "tls-server-end-point":
            return Data(SHA256.hash(data: tlsState.leafCertificateDER))
        default:
            return nil
        }
    }

    var canUseChannelBinding: Bool {
        preferredChannelBindingType != nil
    }

    /// Channel-binding types the server advertised in its stream features.
    var advertisedChannelBindingTypes: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return advertisedTypes
    }
}

/// Supplies Luma's OpenSSL-based TLS processor to Martin's legacy
/// SocketConnector. SecureTransport caps stream TLS at 1.2 and has no keying
/// exporter, so Luma runs its own TLS 1.3 stack (like Monal) while Martin
/// keeps owning the socket and the XMPP framing.
final class LumaTLSNetworkProcessorProvider: NetworkProcessorProvider {
    var providedFeatures: [ConnectorFeature] = [.TLS]

    private let channelBindingStore: LumaChannelBindingStore

    init(channelBindingStore: LumaChannelBindingStore) {
        self.channelBindingStore = channelBindingStore
    }

    func supply() -> SocketConnector.NetworkProcessor {
        LumaTLSNetworkProcessor(channelBindingStore: channelBindingStore)
    }
}

/// OpenSSL TLS 1.3 client processor driven by Martin's byte stream:
/// encrypted socket bytes go in through read(data:), plaintext goes out to
/// the connector; plaintext from the connector is encrypted and handed to
/// the socket through the write delegate.
final class LumaTLSNetworkProcessor: SocketConnector.NetworkProcessor, SSLNetworkProcessor {
    var serverName: String?
    var certificateValidation: SSLCertificateValidation = .default
    var certificateValidationFailed: ((SecTrust?) -> Void)?

    private let channelBindingStore: LumaChannelBindingStore
    private var alpnProtocols: [String] = []

    private var sslContext: OpaquePointer?
    private var ssl: OpaquePointer?
    /// C-string copy of the SNI hostname; OpenSSL keeps the pointer, so the
    /// storage must outlive the SSL object.
    private var storedServerName: [CChar]?
    private var readBIO: OpaquePointer?
    private var writeBIO: OpaquePointer?
    private var handshakeCompleted = false
    private var handshakeFailed = false
    private var pendingPlaintext: [UInt8] = []

    init(channelBindingStore: LumaChannelBindingStore) {
        self.channelBindingStore = channelBindingStore
        super.init()
    }

    deinit {
        SSL_free(ssl)
        SSL_CTX_free(sslContext)
    }

    func setALPNProtocols(_ protocols: [String]) {
        alpnProtocols = protocols
    }

    // MARK: - Byte stream

    /// Encrypted bytes from the socket.
    override func read(data: Data) {
        guard !handshakeFailed else { return }
        ensureTLS()
        guard ssl != nil, let readBIO else { return }
        data.withUnsafeBytes { raw in
            _ = BIO_write(readBIO, raw.baseAddress, Int32(raw.count))
        }
        drive()
    }

    /// Plaintext to encrypt and send to the socket.
    override func write(data: Data, completion: WriteCompletion) {
        guard !handshakeFailed else {
            completion.completed(result: .failure(LumaTLSProcessorError.handshakeFailed))
            return
        }
        pendingPlaintext.append(contentsOf: data)
        ensureTLS()
        drive()
        completion.completed(result: .success(()))
    }

    // MARK: - TLS lifecycle

    private func ensureTLS() {
        guard ssl == nil, !handshakeFailed else { return }
        guard let context = SSL_CTX_new(TLS_client_method()) else {
            handshakeFailed = true
            return
        }
        sslContext = context
        // SSL_CTX_set_min/max_proto_version are C macros, so the Swift
        // importer drops them. Drive the underlying control instead; the
        // values come from <openssl/tls1.h> (TLS1_2_VERSION 0x0303,
        // TLS1_3_VERSION 0x0304) and <openssl/ssl.h>
        // (SSL_CTRL_SET_MIN_PROTO_VERSION 123, SSL_CTRL_SET_MAX_PROTO_VERSION
        // 124). This pins the connection to TLS 1.2–1.3.
        _ = SSL_CTX_ctrl(context, 123, 0x0303, nil)
        _ = SSL_CTX_ctrl(context, 124, 0x0304, nil)
        // The peer must present a certificate, but OpenSSL's own chain
        // verification is disabled: it has no CA store and would reject the
        // server mid-handshake with an "unknown ca" alert. Actual trust
        // evaluation is performed by Luma after the handshake (SecTrust +
        // configured validation), mirroring Martin's custom-validator flow.
        SSL_CTX_set_verify(context, SSL_VERIFY_PEER, { _, _ in 1 })
        guard let connection = SSL_new(context) else {
            handshakeFailed = true
            return
        }
        // This OpenSSL build does not pre-select the connection role in
        // SSL_new; without it SSL_do_handshake fails with
        // "connection type not set".
        SSL_set_connect_state(connection)
        ssl = connection
        if let serverName {
            // SSL_set_tlsext_host_name is a C macro; use SSL_ctrl with
            // SSL_CTRL_SET_TLSEXT_HOSTNAME (55) and TLSEXT_NAMETYPE_host_name
            // (0) instead. OpenSSL keeps the pointer, so the C string must
            // stay alive for the lifetime of the handshake.
            storedServerName = Array(serverName.utf8CString)
            storedServerName?.withUnsafeMutableBufferPointer { buffer in
                _ = SSL_ctrl(connection, 55, 0, buffer.baseAddress)
            }
        }
        if !alpnProtocols.isEmpty {
            var wire: [UInt8] = []
            for proto in alpnProtocols {
                let bytes = Array(proto.utf8)
                wire.append(UInt8(bytes.count))
                wire.append(contentsOf: bytes)
            }
            _ = SSL_set_alpn_protos(connection, wire, UInt32(wire.count))
        }
        let incoming = BIO_new(BIO_s_mem())
        let outgoing = BIO_new(BIO_s_mem())
        guard let incoming, let outgoing else {
            handshakeFailed = true
            return
        }
        readBIO = incoming
        writeBIO = outgoing
        SSL_set_bio(connection, incoming, outgoing)
    }

    private func drive() {
        guard let ssl else { return }
        if !handshakeCompleted, !handshakeFailed {
            driveHandshake()
        }
        if handshakeCompleted, !pendingPlaintext.isEmpty {
            // Copy the pending plaintext before the C call: the array cannot
            // be mutated while it is borrowed by withUnsafeBufferPointer.
            let buffer = pendingPlaintext
            let written = buffer.withUnsafeBufferPointer { raw -> Int32 in
                guard let base = raw.baseAddress, !raw.isEmpty else { return 0 }
                return SSL_write(ssl, base, Int32(raw.count))
            }
            if written > 0 {
                pendingPlaintext.removeFirst(Int(written))
            }
        }
        flushEncryptedOutput()
        if handshakeCompleted {
            emitDecrypted()
            flushEncryptedOutput()
        }
    }

    private func driveHandshake() {
        guard let ssl else { return }
        let result = SSL_do_handshake(ssl)
        if result == 1 {
            handshakeCompleted = true
            completeHandshake()
            return
        }
        switch SSL_get_error(ssl, result) {
        case SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE:
            // Progress made; more bytes needed from either side.
            break
        default:
            handshakeFailed = true
            certificateValidationFailed?(nil)
        }
    }

    private func flushEncryptedOutput() {
        guard let writeBIO else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = BIO_read(writeBIO, &buffer, Int32(buffer.count))
            guard count > 0 else { break }
            super.write(
                data: Data(buffer[0..<Int(count)]),
                completion: .none
            )
        }
    }

    private func emitDecrypted() {
        guard let ssl else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = SSL_read(ssl, &buffer, Int32(buffer.count))
            if count > 0 {
                super.read(data: Data(buffer[0..<Int(count)]))
                continue
            }
            switch SSL_get_error(ssl, count) {
            case SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE:
                return
            case SSL_ERROR_ZERO_RETURN:
                return
            default:
                return
            }
        }
    }

    // MARK: - Handshake completion

    private func completeHandshake() {
        guard let ssl else { return }
        let version = String(cString: SSL_get_version(ssl))
        // SSL_get_cipher_name is a C macro over
        // SSL_CIPHER_get_name(SSL_get_current_cipher(_:)).
        let cipher: String
        if let current = SSL_get_current_cipher(ssl) {
            cipher = String(cString: SSL_CIPHER_get_name(current))
        } else {
            cipher = ""
        }

        var leafDER: Data?
        var chainCertificates: [SecCertificate] = []
        if let chain = SSL_get_peer_cert_chain(ssl) {
            // sk_X509_num / sk_X509_value are C macros; the imported Swift
            // surface exposes OPENSSL_sk_num / OPENSSL_sk_value instead.
            let count = OPENSSL_sk_num(chain)
            for index in 0..<count {
                guard let raw = OPENSSL_sk_value(chain, index) else { continue }
                let certificate = OpaquePointer(raw)
                guard let der = x509DER(certificate) else { continue }
                if leafDER == nil { leafDER = der }
                if let secCertificate = SecCertificateCreateWithData(nil, der as CFData) {
                    chainCertificates.append(secCertificate)
                }
            }
        }
        if leafDER == nil, let certificate = SSL_get1_peer_certificate(ssl) {
            if let der = x509DER(certificate) {
                leafDER = der
                if let secCertificate = SecCertificateCreateWithData(nil, der as CFData) {
                    chainCertificates.insert(secCertificate, at: 0)
                }
            }
            X509_free(certificate)
        }

        guard let leafDER else {
            handshakeFailed = true
            certificateValidationFailed?(nil)
            return
        }

        // Certificate trust evaluation via SecTrust, honouring the
        // connector's configured validation (Luma uses the custom validator).
        var trust: SecTrust?
        if !chainCertificates.isEmpty {
            SecTrustCreateWithCertificates(chainCertificates as CFArray, nil, &trust)
        }
        var validated = false
        if let trust {
            let domain = serverName ?? ""
            switch certificateValidation {
            case .default:
                SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, domain as CFString))
                validated = SecTrustEvaluateWithError(trust, nil)
            case .fingerprint(let fingerprint):
                validated = Self.matchesFingerprint(leafDER, fingerprint: fingerprint)
            case .customValidator(let validator):
                validated = validator(trust)
            }
        }
        guard validated else {
            handshakeFailed = true
            certificateValidationFailed?(trust)
            return
        }

        // RFC 9266 tls-exporter channel binding (TLS 1.3).
        var exporter: Data?
        var exporterBuffer = [UInt8](repeating: 0, count: 32)
        let exporterLabel = "EXPORTER-Channel-Binding"
        let exporterResult = exporterLabel.withCString { label in
            SSL_export_keying_material(
                ssl,
                &exporterBuffer,
                exporterBuffer.count,
                label,
                exporterLabel.utf8.count,
                nil,
                0,
                0
            )
        }
        if exporterResult == 1 {
            exporter = Data(exporterBuffer)
        }

        channelBindingStore.setTLSState(
            LumaTLSState(
                version: version,
                cipher: cipher,
                leafCertificateDER: leafDER,
                exporter: exporter
            )
        )
    }

    private func x509DER(_ certificate: OpaquePointer) -> Data? {
        // Encode into a fixed scratch buffer: X.509 certificates are far
        // smaller than 16 KiB in practice, and this avoids manual OpenSSL
        // memory management in Swift.
        let length = i2d_X509(certificate, nil)
        guard length > 0, length <= 16_384 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(length))
        var copied: Int32 = 0
        buffer.withUnsafeMutableBytes { raw in
            var cursor = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            copied = i2d_X509(certificate, &cursor)
        }
        guard copied == length else { return nil }
        return Data(buffer)
    }

    private static func matchesFingerprint(_ der: Data, fingerprint: String) -> Bool {
        let expected = fingerprint
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        let candidates = [
            Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined(),
            SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined(),
        ]
        return candidates.contains(expected)
    }
}

enum LumaTLSProcessorError: Error {
    case handshakeFailed
}

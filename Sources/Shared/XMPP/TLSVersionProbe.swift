import Foundation
import Security

/// Result of probing the negotiated TLS parameters of the XMPP server:
/// the protocol version and the cipher suite actually agreed upon.
struct TLSProbeResult: Sendable {
    let version: String
    let cipher: String
}

/// Standalone, best-effort probe that negotiates TLS against the same host
/// and port the XMPP connection uses, and reports the negotiated TLS version
/// and cipher suite. It performs the STARTTLS stream handshake (stream
/// header + <starttls/>) when the account does not use Direct TLS, mirroring
/// what Martin's SocketConnector does, then reads the result from
/// SecureTransport. The app's real connection negotiates TLS the same way,
/// so the probe accurately reflects what the server screen displays.
final class TLSVersionProbe: NSObject, StreamDelegate {
    private let host: String
    private let port: UInt32
    private let directTLS: Bool
    private let expectedDomain: String
    private let completion: (TLSProbeResult?) -> Void

    private enum Phase {
        case starting
        case expectingFeatures
        case tlsNegotiating
        case finished
    }

    private var phase: Phase = .starting
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var receivedData = Data()
    private var sentStreamHeader = false
    private var sentStartTLS = false
    private var sawStartTLSOffer = false
    private var sslContext: SSLContext?
    private var runLoop: RunLoop?
    private var finished = false

    private static let activeLock = NSLock()
    private static var activeProbes: Set<TLSVersionProbe> = []

    static func run(
        host: String,
        port: UInt32,
        directTLS: Bool,
        expectedDomain: String,
        completion: @escaping (TLSProbeResult?) -> Void
    ) {
        let probe = TLSVersionProbe(
            host: host,
            port: port,
            directTLS: directTLS,
            expectedDomain: expectedDomain,
            completion: completion
        )
        activeLock.lock()
        activeProbes.insert(probe)
        activeLock.unlock()
        probe.start()
    }

    private init(
        host: String,
        port: UInt32,
        directTLS: Bool,
        expectedDomain: String,
        completion: @escaping (TLSProbeResult?) -> Void
    ) {
        self.host = host
        self.port = port
        self.directTLS = directTLS
        self.expectedDomain = expectedDomain
        self.completion = completion
        super.init()
    }

    private func start() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = RunLoop.current
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocketToHost(
                kCFAllocatorDefault,
                self.host as CFString,
                self.port,
                &readStream,
                &writeStream
            )
            guard let readStream, let writeStream else {
                self.finish(nil)
                return
            }
            self.inputStream = readStream.takeRetainedValue()
            self.outputStream = writeStream.takeRetainedValue()
            self.inputStream?.delegate = self
            self.outputStream?.delegate = self
            self.inputStream?.schedule(in: .current, forMode: .default)
            self.outputStream?.schedule(in: .current, forMode: .default)
            self.inputStream?.open()
            self.outputStream?.open()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, !self.finished else { return }
                self.finish(nil)
            }
            RunLoop.current.run()
        }
        thread.name = "app.luma.tlsProbe"
        thread.start()
    }

    // MARK: - StreamDelegate

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            if phase == .tlsNegotiating {
                reportTLSResult()
            } else if directTLS, phase == .starting {
                configureTLS()
            } else if !sentStreamHeader {
                writeStreamHeader()
            }
        case .hasSpaceAvailable:
            if directTLS { return }
            if !sentStreamHeader {
                writeStreamHeader()
            } else if sawStartTLSOffer, !sentStartTLS {
                writeStartTLS()
            }
        case .hasBytesAvailable:
            readAvailableBytes()
        case .errorOccurred, .endEncountered:
            if phase == .tlsNegotiating {
                reportTLSResult()
            } else if phase != .finished {
                finish(nil)
            }
        default:
            break
        }
    }

    // MARK: - Steps

    private func writeStreamHeader() {
        guard let outputStream else { return }
        let header =
            "<?xml version='1.0'?>"
            + "<stream:stream to='\(expectedDomain)' xmlns='jabber:client' "
            + "xmlns:stream='http://etherx.jabber.org/streams' version='1.0'>"
        let data = Data(header.utf8)
        sentStreamHeader = data.count == outputStream.write(
            [UInt8](data),
            maxLength: data.count
        )
        if sentStreamHeader, !directTLS {
            phase = .expectingFeatures
        }
    }

    private func writeStartTLS() {
        guard let outputStream else { return }
        let startTLS = "<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>"
        let data = Data(startTLS.utf8)
        sentStartTLS = data.count == outputStream.write(
            [UInt8](data),
            maxLength: data.count
        )
    }

    private func readAvailableBytes() {
        guard let inputStream else { return }
        var chunk = [UInt8](repeating: 0, count: 4096)
        while inputStream.hasBytesAvailable {
            let count = inputStream.read(&chunk, maxLength: chunk.count)
            guard count > 0 else { break }
            receivedData.append(contentsOf: chunk[0..<count])
        }
        guard phase == .expectingFeatures else { return }
        let text = String(decoding: receivedData, as: UTF8.self)
        if text.contains("<proceed") {
            configureTLS()
        } else if text.contains("starttls") {
            sawStartTLSOffer = true
            if !sentStartTLS { writeStartTLS() }
        }
    }

    private func configureTLS() {
        guard let inputStream, let outputStream else {
            finish(nil)
            return
        }
        let settings: [String: Any] = [
            kCFStreamSSLValidatesCertificateChain as String: false,
            kCFStreamSSLPeerName as String: expectedDomain,
            kCFStreamSSLLevel as String: StreamSocketSecurityLevel.negotiatedSSL,
        ]
        inputStream.setProperty(
            settings,
            forKey: Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        )
        outputStream.setProperty(
            settings,
            forKey: Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        )
        if let rawContext = outputStream.property(forKey: Stream.PropertyKey(
            rawValue: kCFStreamPropertySSLContext as String
        )) {
            let context = rawContext as! SSLContext
            SSLSetALPNProtocols(context, ["xmpp-client"] as CFArray)
            sslContext = context
        }
        phase = .tlsNegotiating
        inputStream.close()
        outputStream.close()
        inputStream.open()
        outputStream.open()
    }

    private func reportTLSResult() {
        guard phase != .finished else { return }
        phase = .finished
        var protocolVersion = SSLProtocol(rawValue: 0)!
        var cipher: SSLCipherSuite = 0
        if let sslContext {
            SSLGetNegotiatedProtocolVersion(sslContext, &protocolVersion)
            if SSLGetNegotiatedCipher(sslContext, &cipher) != errSecSuccess {
                cipher = 0
            }
        }
        guard let versionDescription = Self.protocolDescription(protocolVersion) else {
            finish(nil)
            return
        }
        finish(TLSProbeResult(
            version: versionDescription,
            cipher: Self.cipherDescription(cipher)
        ))
    }

    private func finish(_ result: TLSProbeResult?) {
        guard !finished else { return }
        finished = true
        phase = .finished
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        completion(result)
        if let runLoop {
            runLoop.perform { CFRunLoopStop(CFRunLoopGetCurrent()) }
        }
        Self.activeLock.lock()
        Self.activeProbes.remove(self)
        Self.activeLock.unlock()
    }

    // MARK: - Descriptions

    /// The protocol constants are marked deprecated on modern SDKs, so match
    /// the raw SecureTransport values instead: TLS 1.3 = 10, TLS 1.2 = 8,
    /// TLS 1.1 = 7, TLS 1.0 = 4, SSL 3.0 = 2.
    static func protocolDescription(_ protocolVersion: SSLProtocol) -> String? {
        switch protocolVersion.rawValue {
        case 10: return "TLS 1.3"
        case 8: return "TLS 1.2"
        case 7: return "TLS 1.1"
        case 4: return "TLS 1.0"
        case 2: return "SSL 3.0"
        default: return nil
        }
    }

    static func cipherDescription(_ cipher: SSLCipherSuite) -> String {
        switch cipher {
        case 0x1301: return "TLS_AES_128_GCM_SHA256"
        case 0x1302: return "TLS_AES_256_GCM_SHA384"
        case 0x1303: return "TLS_CHACHA20_POLY1305_SHA256"
        case 0xC02F: return "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        case 0xC02B: return "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        case 0xC030: return "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        case 0xC02C: return "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        case 0xCCA8: return "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
        case 0xCCA9: return "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
        case 0xCCAA: return "TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
        case 0x009E: return "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256"
        case 0x009F: return "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384"
        case 0x009C: return "TLS_RSA_WITH_AES_128_GCM_SHA256"
        case 0x009D: return "TLS_RSA_WITH_AES_256_GCM_SHA384"
        case 0xC013: return "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"
        case 0xC014: return "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA"
        case 0x003C: return "TLS_RSA_WITH_AES_128_CBC_SHA256"
        case 0x002F: return "TLS_RSA_WITH_AES_128_CBC_SHA"
        case 0x0035: return "TLS_RSA_WITH_AES_256_CBC_SHA"
        default: return String(format: "0x%04X", cipher)
        }
    }
}

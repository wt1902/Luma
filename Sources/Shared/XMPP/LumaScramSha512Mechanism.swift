import CommonCrypto
import CryptoKit
import Foundation
import Martin

/// Pure SCRAM-SHA-512 math per RFC 5802 (SHA-512 / HMAC-SHA-512), kept
/// separate from the Martin mechanism so the proof computation can be
/// unit-tested against reference vectors.
enum SCRAMSHA512 {
    struct ServerFirst {
        let nonce: String
        let salt: Data
        let iterations: Int
        /// XEP-0474: base64 downgrade-protection hash in the optional `h=`
        /// SCRAM attribute, when the server supports the extension.
        let downgradeProtectionHash: String?
    }

    private static let nonceAlphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    static func makeNonce(length: Int = 24) -> String {
        String((0..<length).map { _ in nonceAlphabet.randomElement()! })
    }

    static func parseServerFirst(
        _ message: String,
        expectedNoncePrefix: String
    ) throws -> ServerFirst {
        let pattern = #"^(?:m=[^\000=]+,)?r=([\x21-\x2B\x2D-\x7E]+),s=([a-zA-Z0-9/+=]+),i=(\d+)(?:,h=([a-zA-Z0-9/+=]+))?(?:,.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ClientSaslException.badChallenge(msg: "Failed to parse challenge")
        }
        let fullRange = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: fullRange),
              match.numberOfRanges >= 4,
              let nonceRange = Range(match.range(at: 1), in: message),
              let saltRange = Range(match.range(at: 2), in: message),
              let iterationsRange = Range(match.range(at: 3), in: message) else {
            throw ClientSaslException.badChallenge(msg: "Failed to parse challenge")
        }
        let nonce = String(message[nonceRange])
        let iterations = Int(message[iterationsRange]) ?? 0
        let downgradeProtectionHash: String?
        if let hashRange = Range(match.range(at: 4), in: message) {
            downgradeProtectionHash = String(message[hashRange])
        } else {
            downgradeProtectionHash = nil
        }
        guard nonce.hasPrefix(expectedNoncePrefix),
              let salt = Data(base64Encoded: String(message[saltRange])),
              iterations > 0 else {
            throw ClientSaslException.badChallenge(msg: "Invalid challenge")
        }
        return ServerFirst(
            nonce: nonce,
            salt: salt,
            iterations: iterations,
            downgradeProtectionHash: downgradeProtectionHash
        )
    }

    /// PBKDF2-HMAC-SHA-512 (RFC 5802 \"Hi\" function).
    static func saltedPassword(password: String, salt: Data, iterations: Int) -> [UInt8] {
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        var output = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
            UInt32(iterations),
            &output, output.count
        )
        return output
    }

    static func clientProof(saltedPassword: [UInt8], authMessage: String) -> [UInt8] {
        let clientKey = hmac(saltedPassword, Array("Client Key".utf8))
        let storedKey = digest(clientKey)
        let clientSignature = hmac(storedKey, Array(authMessage.utf8))
        return zip(clientKey, clientSignature).map(^)
    }

    static func serverSignature(saltedPassword: [UInt8], authMessage: String) -> [UInt8] {
        let serverKey = hmac(saltedPassword, Array("Server Key".utf8))
        return hmac(serverKey, Array(authMessage.utf8))
    }

    static func verifyServerSignature(
        saltedPassword: [UInt8],
        authMessage: String,
        finalMessage: String
    ) -> Bool {
        let pattern = #"^(?:e=([^,]+)|v=([a-zA-Z0-9/+=]+)(?:,.*)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: finalMessage,
                  range: NSRange(finalMessage.startIndex..., in: finalMessage)
              ),
              match.numberOfRanges >= 3,
              let vRange = Range(match.range(at: 2), in: finalMessage),
              let value = Data(base64Encoded: String(finalMessage[vRange])) else {
            return false
        }
        return value == Data(serverSignature(saltedPassword: saltedPassword, authMessage: authMessage))
    }

    private static func hmac(_ key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        let code = HMAC<SHA512>.authenticationCode(
            for: Data(data),
            using: SymmetricKey(data: Data(key))
        )
        return Array(code)
    }

    private static func digest(_ data: [UInt8]) -> [UInt8] {
        Array(SHA512.hash(data: Data(data)))
    }
}

/// SCRAM-SHA-512 SASL mechanism. Martin ships only SCRAM-SHA-1 and
/// SCRAM-SHA-256; modern servers prefer SHA-512, so Luma registers this
/// mechanism ahead of Martin's ones.
final class LumaScramSha512Mechanism: SaslMechanism {
    let name = "SCRAM-SHA-512"
    private(set) var status: SaslMechanismStatus = .new

    /// Optional channel-binding store: when present the mechanism verifies
    /// the XEP-0474 downgrade-protection hash from the server and answers
    /// with its own hash.
    private let channelBindingStore: LumaChannelBindingStore?

    private var stage = 0
    private var clientNonce = ""
    private var clientFirstMessageBare = ""
    private var authMessage = ""
    private var saltedPassword: [UInt8] = []

    init(channelBindingStore: LumaChannelBindingStore? = nil) {
        self.channelBindingStore = channelBindingStore
    }

    func reset(scopes: Set<ResetableScope>) {
        guard scopes.contains(.stream) else { return }
        status = .new
        stage = 0
        clientNonce = ""
        clientFirstMessageBare = ""
        authMessage = ""
        saltedPassword = []
    }

    func isAllowedToUse(_ context: Context) -> Bool {
        if case .password(_, _, _) = context.connectionConfiguration.credentials {
            return true
        }
        return false
    }

    func evaluateChallenge(_ input: String?, context: Context) throws -> String? {
        guard status != .completed else {
            guard input == nil else {
                throw ClientSaslException.genericError(msg: "Already authorized")
            }
            return nil
        }
        switch stage {
        case 0:
            guard case .password(_, _, _) = context.connectionConfiguration.credentials else {
                throw ClientSaslException.genericError(msg: "Invalid credentials type")
            }
            clientNonce = SCRAMSHA512.makeNonce()
            clientFirstMessageBare =
                "n=\(context.userBareJid.localPart ?? ""),r=\(clientNonce)"
            stage = 1
            status = .completedExpected
            let first = "n,," + clientFirstMessageBare
            return first.data(using: .utf8)?.base64EncodedString()

        case 1:
            guard case .password(let password, _, _) = context.connectionConfiguration.credentials,
                  let input,
                  let data = Data(base64Encoded: input),
                  let serverFirst = String(data: data, encoding: .utf8) else {
                throw ClientSaslException.badChallenge(msg: "Invalid challenge")
            }
            let parsed = try SCRAMSHA512.parseServerFirst(
                serverFirst,
                expectedNoncePrefix: clientNonce
            )
            // XEP-0474: the optional `h` attribute carries the server's
            // downgrade-protection hash over the advertised mechanism and
            // channel-binding lists. Verify it (a mismatch means a MITM
            // tampered with the lists) and answer with our own hash in `x`.
            var downgradeHashBase64: String?
            if let serverHash = parsed.downgradeProtectionHash {
                channelBindingStore?.markDowngradeProtectionDetected()
                let mechanisms = channelBindingStore?.advertisedSASLMechanismsOrdered ?? []
                let bindingTypes = channelBindingStore?.advertisedChannelBindingTypesOrdered ?? []
                let expected = SCRAMDowngradeProtection.hash(
                    mechanisms: mechanisms,
                    channelBindingTypes: bindingTypes,
                    using: .sha512
                )
                let expectedBase64 = expected.base64EncodedString()
                guard expectedBase64 == serverHash else {
                    throw ClientSaslException.badChallenge(
                        msg: "SCRAM downgrade protection hash mismatch (possible MITM)"
                    )
                }
                downgradeHashBase64 = expectedBase64
            }
            let clientFinalWithoutProof = "c=biws,r=\(parsed.nonce)"
                + (downgradeHashBase64.map { ",x=\($0)" } ?? "")
            authMessage = clientFirstMessageBare + "," + serverFirst + "," + clientFinalWithoutProof
            saltedPassword = SCRAMSHA512.saltedPassword(
                password: password,
                salt: parsed.salt,
                iterations: parsed.iterations
            )
            let proof = SCRAMSHA512.clientProof(
                saltedPassword: saltedPassword,
                authMessage: authMessage
            )
            stage = 2
            let final = clientFinalWithoutProof + ",p=" + Data(proof).base64EncodedString()
            return final.data(using: .utf8)?.base64EncodedString()

        case 2:
            guard let input,
                  let data = Data(base64Encoded: input),
                  let finalMessage = String(data: data, encoding: .utf8),
                  SCRAMSHA512.verifyServerSignature(
                      saltedPassword: saltedPassword,
                      authMessage: authMessage,
                      finalMessage: finalMessage
                  ) else {
                throw ClientSaslException.invalidServerSignature
            }
            status = .completed
            return nil

        default:
            throw ClientSaslException.genericError(msg: "Illegal state")
        }
    }
}


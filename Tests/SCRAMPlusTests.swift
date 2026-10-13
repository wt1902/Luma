import CryptoKit
import XCTest
@testable import Luma

final class SCRAMPlusTests: XCTestCase {
    /// Reference vectors computed with an independent Python
    /// implementation of RFC 5802 SCRAM-SHA-1 with channel binding
    /// (tls-server-end-point, deterministic 32-byte binding data).
    private func referenceExchange() -> SCRAMPlusExchange {
        SCRAMPlusExchange(
            hash: .sha1,
            username: "user",
            password: "pencil",
            channelBindingType: "tls-server-end-point",
            channelBindingData: Data(0..<32),
            clientNonce: "fyko+d2lbbFgONRv9qkxdawL"
        )
    }

    private static let referenceServerFirst =
        "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"

    func testClientFirstMessageMatchesReference() {
        let exchange = referenceExchange()
        let first = exchange.clientFirstMessage.data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(
            first,
            "cD10bHMtc2VydmVyLWVuZC1wb2ludCwsbj11c2VyLHI9ZnlrbytkMmxiYkZnT05Sdjlxa3hkYXdM"
        )
    }

    func testClientFinalMessageMatchesReference() throws {
        let exchange = referenceExchange()
        let final = try exchange.clientFinalMessage(serverFirst: Self.referenceServerFirst)
        let encoded = final.data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(
            encoded,
            "Yz1jRDEwYkhNdGMyVnlkbVZ5TFdWdVpDMXdiMmx1ZEN3c0FBRUNBd1FGQmdjSUNRb0xEQTBPRHhBUkVoTVVGUllYR0JrYUd4d2RIaDg9LHI9ZnlrbytkMmxiYkZnT05Sdjlxa3hkYXdMM3JmY05IWUpZMVpWdldWczdqLHA9RkVLbDNvQU13UFErc0JsYnR6SU1oaGdKSFJjPQ=="
        )
    }

    func testExpectedServerSignatureMatchesReference() throws {
        let exchange = referenceExchange()
        let signature = try exchange.expectedServerSignature(serverFirst: Self.referenceServerFirst)
        XCTAssertEqual(signature.base64EncodedString(), "CCSN72nmVmqopGNXz27xIKr6CxA=")
    }

    func testVerifierValueExtractsOnlyTheBase64Payload() {
        XCTAssertEqual(
            SCRAMPlusExchange.verifierValue(in: "v=DQNSo72nmVmqopGNXz27xIKr6CxA="),
            "DQNSo72nmVmqopGNXz27xIKr6CxA="
        )
        XCTAssertEqual(
            SCRAMPlusExchange.verifierValue(in: "v=abc123"),
            "abc123"
        )
        XCTAssertEqual(
            SCRAMPlusExchange.verifierValue(in: "v=abc123,ext=value"),
            "abc123"
        )
        XCTAssertNil(SCRAMPlusExchange.verifierValue(in: "e=invalid-proof"))
        XCTAssertNil(SCRAMPlusExchange.verifierValue(in: ""))
    }

    func testChannelBindingStoreDerivesEndPointDigest() {
        let store = LumaChannelBindingStore()
        let leaf = Data("certificate".utf8)
        store.setTLSState(
            LumaTLSState(
                version: "TLSv1.3",
                cipher: "TLS_AES_256_GCM_SHA384",
                leafCertificateDER: leaf,
                exporter: Data(0..<32)
            )
        )
        store.setAdvertisedChannelBindingTypes(["tls-exporter", "tls-server-end-point"])
        XCTAssertEqual(store.preferredChannelBindingType, "tls-exporter")
        XCTAssertEqual(
            store.channelBindingData(for: "tls-server-end-point"),
            Data(SHA256.hash(data: leaf))
        )
        XCTAssertEqual(
            store.channelBindingData(for: "tls-exporter"),
            Data(0..<32),
        )
    }

    func testChannelBindingStoreFallsBackToEndPoint() {
        let store = LumaChannelBindingStore()
        store.setTLSState(
            LumaTLSState(
                version: "TLSv1.3",
                cipher: "TLS_AES_256_GCM_SHA384",
                leafCertificateDER: Data("leaf".utf8),
                exporter: nil,
            )
        )
        // Only the certificate digest is available: pick tls-server-end-point.
        store.setAdvertisedChannelBindingTypes(["tls-server-end-point"])
        XCTAssertEqual(store.preferredChannelBindingType, "tls-server-end-point")
        // Nothing usable when the server does not advertise any known type.
        store.setAdvertisedChannelBindingTypes([])
        XCTAssertNil(store.preferredChannelBindingType)
        XCTAssertFalse(store.canUseChannelBinding)
    }
}

import XCTest
@testable import Luma

final class SCRAMDowngradeProtectionTests: XCTestCase {
    /// Reference vector from XEP-0474 §6.3: the server's `h` attribute is
    /// base64(SHA-1('SCRAM-SHA-1\u{1E}SCRAM-SHA-1-PLUS\u{1F}tls-exporter\u{1E}tls-server-end-point')).
    func testHashMatchesXEP0474Example() {
        let hash = SCRAMDowngradeProtection.hash(
            mechanisms: ["SCRAM-SHA-1", "SCRAM-SHA-1-PLUS"],
            channelBindingTypes: ["tls-exporter", "tls-server-end-point"],
            using: .sha1
        )
        XCTAssertEqual(hash.base64EncodedString(), "G6k/rBLDqgOhRRaCuuatSDFkJ08=")
    }

    func testHashSortsListsPerIOctetCollation() {
        // XEP-0474 §5.1 requires i;octet-sorted lists, so advertisement order
        // must not affect the hash.
        let advertisedOrder = SCRAMDowngradeProtection.hash(
            mechanisms: ["SCRAM-SHA-1", "SCRAM-SHA-1-PLUS"],
            channelBindingTypes: ["tls-exporter", "tls-server-end-point"],
            using: .sha1
        )
        let reordered = SCRAMDowngradeProtection.hash(
            mechanisms: ["SCRAM-SHA-1-PLUS", "SCRAM-SHA-1"],
            channelBindingTypes: ["tls-server-end-point", "tls-exporter"],
            using: .sha1
        )
        XCTAssertEqual(advertisedOrder, reordered)
    }

    func testHashOmitsBindingSectionWhenNoTypesAdvertised() {
        let withBindings = SCRAMDowngradeProtection.hash(
            mechanisms: ["SCRAM-SHA-1"],
            channelBindingTypes: ["tls-exporter"],
            using: .sha1
        )
        let withoutBindings = SCRAMDowngradeProtection.hash(
            mechanisms: ["SCRAM-SHA-1"],
            channelBindingTypes: [],
            using: .sha1
        )
        XCTAssertNotEqual(withBindings, withoutBindings)
        // Without bindings the input is exactly the sorted mechanisms with no
        // trailing 0x1F delimiter.
        let expected = SCRAMHash.sha1.hash(data: Data("SCRAM-SHA-1".utf8))
        XCTAssertEqual(withoutBindings, expected)
    }

    func testServerFirstParsesDowngradeProtectionHash() throws {
        let message = "r=12C4CD5C-E38E-4A98-8F6D-15C38F51CCC6a09117a6-ac50-4f2f-93f1-93799c2bddf6,s=QSXCR+Q6sek8bf92,i=4096,h=G6k/rBLDqgOhRRaCuuatSDFkJ08="
        let parsed = try SCRAMSHA512.parseServerFirst(
            message,
            expectedNoncePrefix: "12C4CD5C-E38E-4A98-8F6D-15C38F51CCC6"
        )
        XCTAssertEqual(parsed.downgradeProtectionHash, "G6k/rBLDqgOhRRaCuuatSDFkJ08=")
    }

    func testServerFirstWithoutHashParsesCleanly() throws {
        let message = "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
        let parsed = try SCRAMSHA512.parseServerFirst(
            message,
            expectedNoncePrefix: "fyko+d2lbbFgONRv9qkxdawL"
        )
        XCTAssertNil(parsed.downgradeProtectionHash)
    }

    func testClientFinalIncludesXAttributeWhenHashPresent() throws {
        let exchange = SCRAMPlusExchange(
            hash: .sha1,
            username: "user",
            password: "pencil",
            channelBindingType: "tls-server-end-point",
            channelBindingData: Data(0..<32),
            clientNonce: "fyko+d2lbbFgONRv9qkxdawL"
        )
        let serverFirst = "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096,h=G6k/rBLDqgOhRRaCuuatSDFkJ08="
        let final = try exchange.clientFinalMessage(
            serverFirst: serverFirst,
            downgradeProtectionHashBase64: "G6k/rBLDqgOhRRaCuuatSDFkJ08="
        )
        XCTAssertTrue(final.contains(",x=G6k/rBLDqgOhRRaCuuatSDFkJ08=,"))
        // The same x-attribute must be part of the expected signature's
        // auth message (server reconstructs client-final-without-proof).
        let expected = try exchange.expectedServerSignature(
            serverFirst: serverFirst,
            downgradeProtectionHashBase64: "G6k/rBLDqgOhRRaCuuatSDFkJ08="
        )
        XCTAssertFalse(expected.isEmpty)
    }
}

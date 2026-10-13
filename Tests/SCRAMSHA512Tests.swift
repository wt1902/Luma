import XCTest
@testable import Luma

final class SCRAMSHA512Tests: XCTestCase {
    /// Reference values computed with Python hashlib/hmac for the RFC 5802
    /// vector inputs (password \"pencil\", salt QSXCR+Q6sek8bf92, 4096 rounds).
    private let referenceAuthMessage =
        "n=user,r=fyko+d2lbbFgONRv9qkxdawL"
        + ",r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096"
        + ",c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j"

    func testSaltedPasswordMatchesReference() throws {
        let salt = try XCTUnwrap(Data(base64Encoded: "QSXCR+Q6sek8bf92"))
        let salted = SCRAMSHA512.saltedPassword(password: "pencil", salt: salt, iterations: 4096)
        let hex = salted.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            hex,
            "97382788b15cbe09512d2d20b7e0b8832f8dbab4b7388395440535cd9395e0ffaa1625453b6fde746412bbf903d4bc1d5f448d57f2ac3dd1d2c04979a914ee65"
        )
    }

    func testClientProofMatchesReference() throws {
        let salt = try XCTUnwrap(Data(base64Encoded: "QSXCR+Q6sek8bf92"))
        let salted = SCRAMSHA512.saltedPassword(password: "pencil", salt: salt, iterations: 4096)
        let proof = SCRAMSHA512.clientProof(
            saltedPassword: salted,
            authMessage: referenceAuthMessage
        )
        XCTAssertEqual(
            Data(proof).base64EncodedString(),
            "VdS8LkrURiej1tG6iX+fqCXQfUnBb//d9llXYaH+ylUbDwBUz9geyR9fC4TewskRUM2tlYSalhAT4Aay1Q5dTA=="
        )
    }

    func testServerSignatureMatchesReference() throws {
        let salt = try XCTUnwrap(Data(base64Encoded: "QSXCR+Q6sek8bf92"))
        let salted = SCRAMSHA512.saltedPassword(password: "pencil", salt: salt, iterations: 4096)
        let signature = SCRAMSHA512.serverSignature(
            saltedPassword: salted,
            authMessage: referenceAuthMessage
        )
        XCTAssertEqual(
            Data(signature).base64EncodedString(),
            "14PAAuavk9hxBEkgB0brDxUhvWu+N16meYk+qxVNFqchR8QPohM09Y4Z6WaTCuX4C6nqMB9KIJTDm6RpSM990g=="
        )
    }

    func testVerifyServerSignatureAcceptsAndRejects() throws {
        let salt = try XCTUnwrap(Data(base64Encoded: "QSXCR+Q6sek8bf92"))
        let salted = SCRAMSHA512.saltedPassword(password: "pencil", salt: salt, iterations: 4096)
        let good = "v=14PAAuavk9hxBEkgB0brDxUhvWu+N16meYk+qxVNFqchR8QPohM09Y4Z6WaTCuX4C6nqMB9KIJTDm6RpSM990g=="
        XCTAssertTrue(SCRAMSHA512.verifyServerSignature(
            saltedPassword: salted,
            authMessage: referenceAuthMessage,
            finalMessage: good
        ))
        XCTAssertFalse(SCRAMSHA512.verifyServerSignature(
            saltedPassword: salted,
            authMessage: referenceAuthMessage,
            finalMessage: "v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
        ))
        XCTAssertFalse(SCRAMSHA512.verifyServerSignature(
            saltedPassword: salted,
            authMessage: referenceAuthMessage,
            finalMessage: "e=server-error",
        ))
    }

    func testParseServerFirst() throws {
        let parsed = try SCRAMSHA512.parseServerFirst(
            "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096",
            expectedNoncePrefix: "fyko+d2lbbFgONRv9qkxdawL"
        )
        XCTAssertEqual(parsed.nonce, "fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j")
        XCTAssertEqual(parsed.salt, Data(base64Encoded: "QSXCR+Q6sek8bf92"))
        XCTAssertEqual(parsed.iterations, 4096)
    }

    func testParseServerFirstRejectsWrongNonce() {
        XCTAssertThrowsError(try SCRAMSHA512.parseServerFirst(
            "r=OTHER,s=QSXCR+Q6sek8bf92,i=4096",
            expectedNoncePrefix: "fyko+d2lbbFgONRv9qkxdawL"
        ))
    }
}


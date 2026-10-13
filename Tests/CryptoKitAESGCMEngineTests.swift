import XCTest

@testable import Luma

final class CryptoKitAESGCMEngineTests: XCTestCase {
    func testRoundTrip() {
        let engine = CryptoKitAESGCMEngine()
        let key = Data(repeating: 0x31, count: 16)
        let iv = Data(repeating: 0x22, count: 12)
        let plaintext = Data("hello omemo".utf8)
        var ciphertext = Data()
        var tag = Data()

        XCTAssertTrue(
            engine.encrypt(iv: iv, key: key, message: plaintext, output: &ciphertext, tag: &tag))

        var decrypted = Data()
        XCTAssertTrue(
            engine.decrypt(iv: iv, key: key, encoded: ciphertext, auth: tag, output: &decrypted))
        XCTAssertEqual(decrypted, plaintext)
    }

    func testModifiedTagFails() {
        let engine = CryptoKitAESGCMEngine()

        let key = Data(repeating: 0x31, count: 16)
        let iv = Data(repeating: 0x22, count: 12)

        var ciphertext = Data()
        var tag = Data()

        guard
            engine.encrypt(
                iv: iv,
                key: key,
                message: Data("secret".utf8),
                output: &ciphertext,
                tag: &tag
            )
        else {
            XCTFail("AES-GCM encryption unexpectedly failed")
            return
        }

        XCTAssertEqual(tag.count, 16)

        guard tag.count == 16 else {
            return
        }

        var modifiedTag = tag
        modifiedTag[modifiedTag.startIndex] ^= 0x01

        var decrypted = Data()

        XCTAssertFalse(
            engine.decrypt(
                iv: iv,
                key: key,
                encoded: ciphertext,
                auth: modifiedTag,
                output: &decrypted
            )
        )
    }
}

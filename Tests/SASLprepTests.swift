import XCTest
@testable import Luma

final class SASLprepTests: XCTestCase {
    func testASCIIPasswordIsUnchanged() throws {
        XCTAssertEqual(try SASLprep.prepare("password123"), "password123")
    }

    func testCyrillicPasswordIsUnchanged() throws {
        XCTAssertEqual(try SASLprep.prepare("пароль123"), "пароль123")
    }

    func testNonASCIISpacesMapToSpace() throws {
        XCTAssertEqual(try SASLprep.prepare("a\u{00A0}b"), "a b")
        XCTAssertEqual(try SASLprep.prepare("a\u{202F}b"), "a b")
    }

    func testMappedToNothingCharactersAreRemoved() throws {
        XCTAssertEqual(try SASLprep.prepare("a\u{00AD}b"), "ab")
        XCTAssertEqual(try SASLprep.prepare("a\u{FE00}b"), "ab")
    }

    func testZeroWidthSpaceMapsToSpacePerRFC4013() throws {
        // RFC 4013 C.1.2 maps U+200B to SPACE, overriding RFC 3454 B.1.
        XCTAssertEqual(try SASLprep.prepare("a\u{200B}b"), "a b")
    }

    func testFullwidthAndCompatibilityFormsAreNormalized() throws {
        XCTAssertEqual(try SASLprep.prepare("ＡＢＣ"), "ABC")
        XCTAssertEqual(try SASLprep.prepare("①"), "1")
    }

    func testDecomposedAccentIsComposed() throws {
        XCTAssertEqual(try SASLprep.prepare("e\u{0301}"), "é")
    }

    func testMixedPassword() throws {
        XCTAssertEqual(try SASLprep.prepare("Пароль\u{00A0}①"), "Пароль 1")
    }

    func testProhibitedCharactersThrow() {
        XCTAssertThrowsError(try SASLprep.prepare("a\u{0007}b"))
        XCTAssertThrowsError(try SASLprep.prepare("a\u{007F}b"))
        XCTAssertThrowsError(try SASLprep.prepare("a\u{FFFE}b"))
        XCTAssertThrowsError(try SASLprep.prepare("a\u{202E}b"))
    }
}


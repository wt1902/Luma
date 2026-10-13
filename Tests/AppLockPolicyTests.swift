import XCTest
@testable import Luma

final class AppLockPolicyTests: XCTestCase {
    func testMinimumLengthIsFour() {
        XCTAssertEqual(AppLockPolicy.minimumLength, 4)
    }

    func testValidationRejectsShortPasscodes() {
        XCTAssertFalse(AppLockPolicy.isValid(""))
        XCTAssertFalse(AppLockPolicy.isValid("1"))
        XCTAssertFalse(AppLockPolicy.isValid("123"))
    }

    func testValidationAcceptsFourOrMoreCharacters() {
        XCTAssertTrue(AppLockPolicy.isValid("1234"))
        XCTAssertTrue(AppLockPolicy.isValid("пароль"))
        XCTAssertTrue(AppLockPolicy.isValid("long-passcode"))
    }
}


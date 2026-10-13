import XCTest
@testable import Luma

final class AccountConfigurationTests: XCTestCase {
    func testValidAccountIsNormalized() throws {
        let account = AccountConfiguration(
            jid: "  Alice@Example.ORG  ",
            resource: "",
            manualHost: " xmpp.example.org ",
            manualPort: 5222
        )

        let validated = try account.validated()

        XCTAssertEqual(validated.normalizedJID, "alice@example.org")
        XCTAssertEqual(validated.domain, "example.org")
        XCTAssertTrue(validated.effectiveResource.hasPrefix("Luma-"))
        XCTAssertNotEqual(validated.effectiveResource, DeviceResource.legacyDefault)
        XCTAssertEqual(validated.effectiveResource, DeviceResource.default)
        XCTAssertEqual(validated.manualHost, "xmpp.example.org")
    }

    func testLegacyDefaultResourceIsMigratedToAUniqueDeviceResource() throws {
        let account = try AccountConfiguration(
            jid: "alice@example.org",
            resource: "Luma"
        ).validated()

        XCTAssertTrue(account.effectiveResource.hasPrefix("Luma-"))
        XCTAssertNotEqual(account.effectiveResource, "Luma")
    }

    func testExplicitResourceIsPreserved() throws {
        let account = try AccountConfiguration(
            jid: "alice@example.org",
            resource: "  MyDevice  "
        ).validated()

        XCTAssertEqual(account.effectiveResource, "MyDevice")
    }

    func testInvalidJIDIsRejected() {
        XCTAssertThrowsError(try AccountConfiguration(jid: "not-a-jid").validated())
        XCTAssertThrowsError(try AccountConfiguration(jid: "@example.org").validated())
        XCTAssertThrowsError(try AccountConfiguration(jid: "alice@").validated())
    }

    func testInvalidPortIsRejected() {
        XCTAssertThrowsError(
            try AccountConfiguration(jid: "alice@example.org", manualPort: 70_000).validated()
        )
    }
}


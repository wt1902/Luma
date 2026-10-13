import Foundation
import XCTest
@testable import Luma

final class EncryptionPreferenceTests: XCTestCase {
    func testResolutionUsesGlobalDefaultAndPerChatOverride() {
        XCTAssertTrue(EncryptionPreference.inheritGlobal.resolved(globalEnabled: true))
        XCTAssertFalse(EncryptionPreference.inheritGlobal.resolved(globalEnabled: false))
        XCTAssertTrue(EncryptionPreference.enabled.resolved(globalEnabled: false))
        XCTAssertFalse(EncryptionPreference.disabled.resolved(globalEnabled: true))
    }

    func testGlobalSettingIsStoredPerAccount() throws {
        let suite = "LumaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AccountPreferences(defaults: defaults)

        XCTAssertTrue(preferences.encryptionEnabled(for: "alice@example.org"))
        preferences.setEncryptionEnabled(false, for: "alice@example.org")

        XCTAssertFalse(preferences.encryptionEnabled(for: "alice@example.org"))
        XCTAssertTrue(preferences.encryptionEnabled(for: "bob@example.org"))
    }
}

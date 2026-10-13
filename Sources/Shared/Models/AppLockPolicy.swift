import Foundation

/// Pure policy for the app-lock passcode: minimum length and validation.
/// Kept separate from the Keychain storage so it is unit-testable.
enum AppLockPolicy {
    static let minimumLength = 4

    static func isValid(_ passcode: String) -> Bool {
        passcode.count >= minimumLength
    }
}


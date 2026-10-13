import Foundation
import Security

/// Stores the app-lock passcode in the Keychain and the lock preferences in
/// UserDefaults. The lock is a UI-level gate: the passcode is kept only in
/// the Keychain and is never mirrored into memory beyond verification.
final class AppLockVault {
    private let service = "app.luma.chat.applock"
    private let account = "applock-passcode"
    private let enabledKey = "appLockEnabled"
    private let biometricKey = "appLockBiometricUnlock"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var biometricUnlockEnabled: Bool {
        get { defaults.bool(forKey: biometricKey) }
        set { defaults.set(newValue, forKey: biometricKey) }
    }

    func save(passcode: String) throws {
        let data = Data(passcode.utf8)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppLockVaultError.unhandled(updateStatus)
        }
        var insertion = baseQuery
        insertion[kSecValueData] = data
#if !os(macOS)
        insertion[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppLockVaultError.unhandled(addStatus)
        }
    }

    func deletePasscode() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppLockVaultError.unhandled(status)
        }
    }

    func verify(passcode: String) -> Bool {
        guard let stored = storedPasscode() else { return false }
        return passcode == stored
    }

    private func storedPasscode() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }
}

enum AppLockVaultError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "Не удалось обратиться к Keychain (\(status))."
        }
    }
}


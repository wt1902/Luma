import Foundation

final class AccountPreferences {
    private let defaults: UserDefaults
    private let accountKey = "luma.active-account.v1"
    private let accountsKey = "luma.accounts.v1"
    private let encryptionSettingsKey = "luma.encryption-settings.v1"
    private let chatStateSettingsKey = "luma.chat-state-settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AccountConfiguration? {
        guard let data = defaults.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(AccountConfiguration.self, from: data)
    }

    /// Returns every configured account. The original single-account key is
    /// migrated lazily so existing installations keep working.
    func loadAccounts() -> [AccountConfiguration] {
        if let data = defaults.data(forKey: accountsKey),
           let accounts = try? JSONDecoder().decode([AccountConfiguration].self, from: data) {
            return accounts
        }
        guard let account = load() else { return [] }
        return [account]
    }

    func saveAccounts(_ accounts: [AccountConfiguration]) throws {
        let normalized = accounts.reduce(into: [String: AccountConfiguration]()) { result, account in
            result[account.normalizedJID] = account
        }.values.sorted { $0.normalizedJID < $1.normalizedJID }
        defaults.set(try JSONEncoder().encode(normalized), forKey: accountsKey)
        if let active = load(), normalized.contains(where: { $0.normalizedJID == active.normalizedJID }) {
            try save(active)
        } else if let first = normalized.first {
            try save(first)
        } else {
            clear()
        }
    }

    func add(_ account: AccountConfiguration) throws {
        try saveAccounts(loadAccounts() + [account])
    }

    func remove(jid: String) throws {
        try saveAccounts(loadAccounts().filter { $0.normalizedJID != jid.lowercased() })
    }

    func save(_ account: AccountConfiguration) throws {
        let data = try JSONEncoder().encode(account)
        defaults.set(data, forKey: accountKey)
    }

    func clear() {
        defaults.removeObject(forKey: accountKey)
    }

    func encryptionEnabled(for accountJID: String) -> Bool {
        let settings = defaults.dictionary(forKey: encryptionSettingsKey) as? [String: Bool]
        return settings?[accountJID.lowercased()] ?? true
    }

    func setEncryptionEnabled(_ enabled: Bool, for accountJID: String) {
        var settings = (defaults.dictionary(forKey: encryptionSettingsKey) as? [String: Bool]) ?? [:]
        settings[accountJID.lowercased()] = enabled
        defaults.set(settings, forKey: encryptionSettingsKey)
    }

    func chatStatesEnabled(for accountJID: String) -> Bool {
        let settings = defaults.dictionary(forKey: chatStateSettingsKey) as? [String: Bool]
        return settings?[accountJID.lowercased()] ?? true
    }

    func setChatStatesEnabled(_ enabled: Bool, for accountJID: String) {
        var settings = (defaults.dictionary(forKey: chatStateSettingsKey) as? [String: Bool]) ?? [:]
        settings[accountJID.lowercased()] = enabled
        defaults.set(settings, forKey: chatStateSettingsKey)
    }
}

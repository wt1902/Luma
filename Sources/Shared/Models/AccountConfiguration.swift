import Foundation

struct AccountConfiguration: Codable, Equatable, Hashable, Identifiable, Sendable {
    var jid: String
    var displayName: String
    var resource: String
    var manualHost: String?
    var manualPort: Int?
    var usesDirectTLS: Bool

    var id: String { normalizedJID }

    var normalizedJID: String {
        jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var domain: String? {
        let pieces = normalizedJID.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2, !pieces[1].isEmpty else { return nil }
        return String(pieces[1])
    }

    var effectiveResource: String {
        let trimmed = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == DeviceResource.legacyDefault {
            return DeviceResource.default
        }
        return trimmed
    }

    init(
        jid: String,
        displayName: String = "",
        resource: String = "Luma",
        manualHost: String? = nil,
        manualPort: Int? = nil,
        usesDirectTLS: Bool = false
    ) {
        self.jid = jid
        self.displayName = displayName
        self.resource = resource
        self.manualHost = manualHost?.nilIfBlank
        self.manualPort = manualPort
        self.usesDirectTLS = usesDirectTLS
    }

    func validated() throws -> AccountConfiguration {
        let normalized = normalizedJID
        let pieces = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              !pieces[0].isEmpty,
              !pieces[1].isEmpty,
              !normalized.contains(where: { $0.isWhitespace }) else {
            throw AccountValidationError.invalidJID
        }

        if let manualHost, manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AccountValidationError.invalidHost
        }

        if let manualPort, !(1...65_535).contains(manualPort) {
            throw AccountValidationError.invalidPort
        }

        var copy = self
        copy.jid = normalized
        copy.manualHost = manualHost?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        copy.resource = effectiveResource
        return copy
    }
}

enum AccountValidationError: LocalizedError {
    case invalidJID
    case invalidHost
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidJID:
            return "Введите полный JID в формате user@example.org."
        case .invalidHost:
            return "Адрес сервера не может быть пустым."
        case .invalidPort:
            return "Порт должен быть числом от 1 до 65535."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}


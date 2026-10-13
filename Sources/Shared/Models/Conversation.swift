import Foundation
import SwiftData

@Model
final class Conversation {
    enum Kind: String, Codable {
        case direct
        case group
    }

    @Attribute(.unique) var jid: String
    var displayName: String
    var lastMessage: String
    var lastActivity: Date
    var unreadCount: Int
    var isOnline: Bool
    var isPinned: Bool
    var encryptionPreference: EncryptionPreference
    var kind: Kind
    var groupNickname: String?
    var isGroupJoined: Bool
    var shouldAutojoin: Bool
    var occupantCount: Int
    var invitedBy: String?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(
        jid: String,
        displayName: String? = nil,
        lastMessage: String = "",
        lastActivity: Date = .distantPast,
        unreadCount: Int = 0,
        isOnline: Bool = false,
        isPinned: Bool = false,
        encryptionPreference: EncryptionPreference = .inheritGlobal,
        kind: Kind = .direct,
        groupNickname: String? = nil,
        isGroupJoined: Bool = false,
        shouldAutojoin: Bool = false,
        occupantCount: Int = 0,
        invitedBy: String? = nil
    ) {
        let normalized = jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.jid = normalized
        self.displayName = displayName?.nilIfBlank ?? normalized
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.isOnline = isOnline
        self.isPinned = isPinned
        self.encryptionPreference = encryptionPreference
        self.kind = kind
        self.groupNickname = groupNickname?.nilIfBlank
        self.isGroupJoined = isGroupJoined
        self.shouldAutojoin = shouldAutojoin
        self.occupantCount = max(0, occupantCount)
        self.invitedBy = invitedBy?.nilIfBlank
    }

    var isGroup: Bool { kind == .group }

    var initials: String {
        let source = displayName == jid ? (jid.split(separator: "@").first.map(String.init) ?? jid) : displayName
        let words = source.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return String(source.prefix(1)).uppercased()
        }
        return String(letters).uppercased()
    }

    var colorSeed: UInt64 {
        jid.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

/// A row in the cross-account inbox. JID alone is not a stable identity when
/// two logged-in accounts have the same contact or a self-chat.
struct AccountConversation: Identifiable {
    let account: AccountConfiguration
    let conversation: Conversation

    var id: String { "\(account.normalizedJID)|\(conversation.jid)" }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

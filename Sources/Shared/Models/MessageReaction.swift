import Foundation

struct MessageReaction: Codable, Identifiable, Hashable, Sendable {
    let senderJID: String
    var emojis: [String]
    var updatedAt: Date

    var id: String { senderJID }

    init(senderJID: String, emojis: [String], updatedAt: Date = Date()) {
        self.senderJID = Self.normalizedJID(senderJID)
        self.emojis = MessageReactionPolicy.sanitized(emojis)
        self.updatedAt = updatedAt
    }

    private static func normalizedJID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct MessageReactionSummary: Identifiable, Hashable, Sendable {
    let emoji: String
    let count: Int
    let includesOwnReaction: Bool

    var id: String { emoji }
}

enum MessageReactionPolicy {
    static let quickChoices = ["👍", "❤️", "😂", "😮", "😢", "🔥"]

    static func sanitized(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count == 1,
                  value.utf8.count <= 64,
                  value.unicodeScalars.contains(where: { $0.properties.isEmoji }),
                  seen.insert(value).inserted else { return nil }
            return value
        }
    }

    static func summaries(
        reactions: [MessageReaction],
        ownJID: String?
    ) -> [MessageReactionSummary] {
        let normalizedOwnJID = ownJID.map(bareJID)
        var counts: [String: Int] = [:]
        var ownValues: Set<String> = []

        for reaction in reactions {
            let values = sanitized(reaction.emojis)
            for emoji in values {
                counts[emoji, default: 0] += 1
            }
            if normalizedOwnJID == bareJID(reaction.senderJID) {
                ownValues.formUnion(values)
            }
        }

        return counts.keys.sorted().map { emoji in
            MessageReactionSummary(
                emoji: emoji,
                count: counts[emoji, default: 0],
                includesOwnReaction: ownValues.contains(emoji)
            )
        }
    }

    static func bareJID(_ value: String) -> String {
        value
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .lowercased()
            ?? value.lowercased()
    }
}

extension ChatMessage {
    var reactionIdentifier: String? {
        isGroupMessage ? stanzaID : clientID
    }

    var canBeReactedTo: Bool {
        guard !isRetracted,
              kind != .system,
              direction == .incoming || delivery != .sending else { return false }
        return !isGroupMessage || stanzaID != nil
    }

    func reactionSummaries(ownJID: String?) -> [MessageReactionSummary] {
        MessageReactionPolicy.summaries(reactions: reactions, ownJID: ownJID)
    }

    func reactionEmojis(from senderJID: String) -> [String] {
        let sender = MessageReactionPolicy.bareJID(senderJID)
        return reactions.first {
            MessageReactionPolicy.bareJID($0.senderJID) == sender
        }?.emojis ?? []
    }
}

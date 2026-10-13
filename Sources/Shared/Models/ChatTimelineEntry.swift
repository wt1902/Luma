import Foundation

/// A cached presentation row for the selected chat. Building day boundaries
/// once per message mutation avoids walking the full history during every
/// scroll-position or composer-state update.
struct ChatTimelineEntry: Identifiable, Hashable {
    let message: ChatMessage
    let startsNewDay: Bool

    var id: String { message.clientID }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message.clientID == rhs.message.clientID
            && lhs.startsNewDay == rhs.startsNewDay
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(message.clientID)
        hasher.combine(startsNewDay)
    }

    static func make(
        from messages: [ChatMessage],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ChatTimelineEntry] {
        var previousTimestamp: Date?
        return messages.map { message in
            let startsNewDay = previousTimestamp.map {
                !calendar.isDate($0, inSameDayAs: message.timestamp)
            } ?? true
            previousTimestamp = message.timestamp
            return ChatTimelineEntry(
                message: message,
                startsNewDay: startsNewDay
            )
        }
    }
}

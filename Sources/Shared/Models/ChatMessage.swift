import Foundation
import SwiftData

@Model
final class ChatMessage {
    enum Direction: String, Codable {
        case incoming
        case outgoing
    }

    enum Delivery: String, Codable {
        case sending
        case sent
        case delivered
        case failed
        case read

        /// Monotonic promotion used when the same outgoing message is replayed
        /// from MAM/MUC-MAM or Carbons: a copy that was already delivered or
        /// read locally must never be downgraded by an archive replay carrying
        /// `.sent`. `.failed` is sticky in both directions — an archive
        /// replay must not silently "fix" a failed send; the user resends it
        /// explicitly.
        func merged(with other: Delivery) -> Delivery {
            guard self != .failed, other != .failed else { return .failed }
            return other.rank > self.rank ? other : self
        }

        private var rank: Int {
            switch self {
            case .sending: return 0
            case .sent: return 1
            case .delivered: return 2
            case .read: return 3
            case .failed: return -1
            }
        }
    }

    enum Security: String, Codable {
        case omemo
        case plaintext
        case decryptionFailed
    }

    enum Kind: String, Codable {
        case text
        case attachment
        case photo
        case video
        case audio
        case voice
        case videoNote
        case location
        case system

        var isMedia: Bool {
            switch self {
            case .attachment, .photo, .video, .audio, .voice, .videoNote:
                return true
            case .text, .location, .system:
                return false
            }
        }
    }

    @Attribute(.unique) var clientID: String
    var conversationID: String
    var senderJID: String
    var body: String
    var timestamp: Date
    var direction: Direction
    var delivery: Delivery
    var security: Security
    var kind: Kind
    var remoteAttachmentURL: String?
    var localFilename: String?
    var mimeType: String?
    var duration: TimeInterval?
    var byteCount: Int?
    var encryptionFingerprint: String?
    var editedAt: Date?
    var replyToID: String?
    var replyToJID: String?
    var replyPreview: String?
    var forwardedFrom: String?
    var retractedAt: Date?
    var originID: String?
    var stanzaID: String?
    var senderDisplayName: String?
    var isGroupMessage: Bool
    var callHistory: CallHistoryMetadata?
    var reactions: [MessageReaction]

    var conversation: Conversation?

    init(
        id: String = UUID().uuidString,
        conversationID: String,
        senderJID: String,
        body: String,
        timestamp: Date = Date(),
        direction: Direction,
        delivery: Delivery,
        security: Security,
        kind: Kind = .text,
        remoteAttachmentURL: String? = nil,
        localFilename: String? = nil,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        byteCount: Int? = nil,
        encryptionFingerprint: String? = nil,
        editedAt: Date? = nil,
        replyToID: String? = nil,
        replyToJID: String? = nil,
        replyPreview: String? = nil,
        forwardedFrom: String? = nil,
        retractedAt: Date? = nil,
        originID: String? = nil,
        stanzaID: String? = nil,
        senderDisplayName: String? = nil,
        isGroupMessage: Bool = false,
        callHistory: CallHistoryMetadata? = nil,
        reactions: [MessageReaction] = []
    ) {
        self.clientID = id
        self.conversationID = conversationID.lowercased()
        self.senderJID = Self.normalizedSenderJID(senderJID)
        self.body = body
        self.timestamp = timestamp
        self.direction = direction
        self.delivery = delivery
        self.security = security
        self.kind = kind
        self.remoteAttachmentURL = remoteAttachmentURL
        self.localFilename = localFilename
        self.mimeType = mimeType
        self.duration = duration
        self.byteCount = byteCount
        self.encryptionFingerprint = encryptionFingerprint
        self.editedAt = editedAt
        self.replyToID = replyToID
        self.replyToJID = replyToJID.map(Self.normalizedSenderJID)
        self.replyPreview = replyPreview
        self.forwardedFrom = forwardedFrom
        self.retractedAt = retractedAt
        self.originID = originID ?? (direction == .outgoing ? id : nil)
        self.stanzaID = stanzaID
        self.senderDisplayName = senderDisplayName
        self.isGroupMessage = isGroupMessage
        self.callHistory = callHistory
        self.reactions = reactions
    }

    var canBeEdited: Bool {
        !isRetracted
            && !isGroupMessage
            && direction == .outgoing
            && kind == .text
            && (delivery == .sent || delivery == .delivered || delivery == .read)
    }

    var isRetracted: Bool {
        retractedAt != nil
    }

    var canBeRepliedTo: Bool {
        !isRetracted
            && kind != .system
            && (!isGroupMessage || stanzaID != nil)
    }

    var canBeForwarded: Bool {
        !isRetracted && kind != .system
    }

    var canBeRetracted: Bool {
        direction == .outgoing
            && !isGroupMessage
            && !isRetracted
            && kind != .system
            && (delivery == .sent || delivery == .delivered || delivery == .read)
    }

    var replyIdentifier: String? {
        isGroupMessage ? stanzaID : clientID
    }

    var quotePreview: String {
        if isRetracted { return "Сообщение удалено" }
        let value = kind == .text ? body : previewText
        let normalized =
            value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 140 else { return normalized }
        return String(normalized.prefix(137)) + "…"
    }

    var previewText: String {
        if isRetracted { return "🚫 Сообщение удалено" }
        if let callHistory {
            let icon = callHistory.isVideo ? "🎥" : "📞"
            return "\(icon) \(callTitle)"
        }
        switch kind {
        case .attachment:
            return "📎 \(localFilename ?? "Вложение")"
        case .photo:
            return "📷 Фото"
        case .video:
            return "🎬 Видео"
        case .audio:
            return "🎵 \(localFilename ?? "Аудио")"
        case .voice:
            return "🎙 Голосовое сообщение"
        case .videoNote:
            return "⭕️ Видеосообщение"
        case .location:
            return "📍 Геопозиция"
        case .text, .system:
            return body
        }
    }

    var callTitle: String {
        guard let callHistory else { return body }
        let media = callHistory.isVideo ? "видеозвонок" : "аудиозвонок"
        switch callHistory.outcome {
        case .completed:
            return direction == .incoming ? "Входящий \(media)" : "Исходящий \(media)"
        case .declined:
            return "Отклонённый \(media)"
        case .missed:
            return "Пропущенный \(media)"
        case .cancelled:
            return "Отменённый \(media)"
        case .unanswered:
            return "Нет ответа"
        case .failed:
            return "Неудачный \(media)"
        case .answeredElsewhere:
            return "Звонок принят на другом устройстве"
        }
    }

    var callSubtitle: String? {
        guard let callHistory else { return nil }
        switch callHistory.outcome {
        case .completed:
            guard let duration else { return "Звонок завершён" }
            return "Длительность \(Self.formattedCallDuration(duration))"
        case .declined:
            return direction == .incoming
                ? "Вы отклонили звонок"
                : "Собеседник отклонил звонок"
        case .missed:
            return "Вы не ответили"
        case .cancelled:
            return direction == .outgoing
                ? "Вы отменили вызов"
                : "Собеседник отменил вызов"
        case .unanswered:
            return "Собеседник не ответил"
        case .failed:
            return "Соединение не установлено"
        case .answeredElsewhere:
            return "Ответ с другого устройства"
        }
    }

    private static func formattedCallDuration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        if seconds >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                seconds / 3_600,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func normalizedSenderJID(_ value: String) -> String {
        guard let slash = value.firstIndex(of: "/") else { return value.lowercased() }
        let bare = value[..<slash].lowercased()
        return bare + String(value[slash...])
    }

    var hasText: Bool {
        // 1. Удалённые сообщения не копируем
        guard !isRetracted else { return false }

        // 2. Исключаем системные уведомления
        guard kind != .system else { return false }

        // 3. Текст считается существующим, если body не пустая строка (с обрезкой пробелов)
        return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

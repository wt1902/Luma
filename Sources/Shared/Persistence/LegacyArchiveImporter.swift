import Foundation

/// Reads the legacy JSON snapshot and converts it into SwiftData `@Model`
/// objects once, so existing history survives the migration from the JSON file.
/// Decoding mirrors the tolerant decoders of the removed `ChatArchive`:
/// every field that was ever optional or added later falls back to a default,
/// so snapshots written by older schema versions still import.
enum LegacyArchiveImporter {
    struct LegacyConversation: Codable {
        enum Kind: String, Codable { case direct, group }
        var id: String
        var jid: String
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

        init(
            id: String,
            jid: String,
            displayName: String,
            lastMessage: String,
            lastActivity: Date,
            unreadCount: Int,
            isOnline: Bool,
            isPinned: Bool,
            encryptionPreference: EncryptionPreference,
            kind: Kind,
            groupNickname: String? = nil,
            isGroupJoined: Bool,
            shouldAutojoin: Bool,
            occupantCount: Int,
            invitedBy: String? = nil
        ) {
            self.id = id
            self.jid = jid
            self.displayName = displayName
            self.lastMessage = lastMessage
            self.lastActivity = lastActivity
            self.unreadCount = unreadCount
            self.isOnline = isOnline
            self.isPinned = isPinned
            self.encryptionPreference = encryptionPreference
            self.kind = kind
            self.groupNickname = groupNickname
            self.isGroupJoined = isGroupJoined
            self.shouldAutojoin = shouldAutojoin
            self.occupantCount = occupantCount
            self.invitedBy = invitedBy
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case jid
            case displayName
            case lastMessage
            case lastActivity
            case unreadCount
            case isOnline
            case isPinned
            case encryptionPreference
            case kind
            case groupNickname
            case isGroupJoined
            case shouldAutojoin
            case occupantCount
            case invitedBy
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            jid = try values.decode(String.self, forKey: .jid)
            id = try values.decodeIfPresent(String.self, forKey: .id) ?? jid.lowercased()
            displayName = try values.decode(String.self, forKey: .displayName)
            lastMessage = try values.decode(String.self, forKey: .lastMessage)
            lastActivity = try values.decode(Date.self, forKey: .lastActivity)
            unreadCount = try values.decode(Int.self, forKey: .unreadCount)
            isOnline = try values.decode(Bool.self, forKey: .isOnline)
            isPinned = try values.decode(Bool.self, forKey: .isPinned)
            encryptionPreference = try values.decodeIfPresent(
                EncryptionPreference.self,
                forKey: .encryptionPreference
            ) ?? .inheritGlobal
            kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .direct
            groupNickname = try values.decodeIfPresent(String.self, forKey: .groupNickname)
            isGroupJoined = try values.decodeIfPresent(Bool.self, forKey: .isGroupJoined) ?? false
            shouldAutojoin = try values.decodeIfPresent(Bool.self, forKey: .shouldAutojoin) ?? false
            occupantCount = max(0, try values.decodeIfPresent(Int.self, forKey: .occupantCount) ?? 0)
            invitedBy = try values.decodeIfPresent(String.self, forKey: .invitedBy)
        }
    }

    struct LegacyMessage: Codable {
        enum Direction: String, Codable { case incoming, outgoing }
        enum Delivery: String, Codable { case sending, sent, delivered, failed }
        enum Security: String, Codable { case omemo, plaintext, decryptionFailed }
        enum Kind: String, Codable {
            case text, attachment, photo, video, audio, voice, videoNote, location, system
        }
        var id: String
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

        init(
            id: String,
            conversationID: String,
            senderJID: String,
            body: String,
            timestamp: Date,
            direction: Direction,
            delivery: Delivery,
            security: Security,
            kind: Kind,
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
            self.id = id
            self.conversationID = conversationID
            self.senderJID = senderJID
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
            self.replyToJID = replyToJID
            self.replyPreview = replyPreview
            self.forwardedFrom = forwardedFrom
            self.retractedAt = retractedAt
            self.originID = originID
            self.stanzaID = stanzaID
            self.senderDisplayName = senderDisplayName
            self.isGroupMessage = isGroupMessage
            self.callHistory = callHistory
            self.reactions = reactions
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case conversationID
            case senderJID
            case body
            case timestamp
            case direction
            case delivery
            case security
            case kind
            case remoteAttachmentURL
            case localFilename
            case mimeType
            case duration
            case byteCount
            case encryptionFingerprint
            case editedAt
            case replyToID
            case replyToJID
            case replyPreview
            case forwardedFrom
            case retractedAt
            case originID
            case stanzaID
            case senderDisplayName
            case isGroupMessage
            case callHistory
            case reactions
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            conversationID = try values.decode(String.self, forKey: .conversationID).lowercased()
            senderJID = try values.decode(String.self, forKey: .senderJID)
            body = try values.decode(String.self, forKey: .body)
            timestamp = try values.decode(Date.self, forKey: .timestamp)
            direction = try values.decode(Direction.self, forKey: .direction)
            delivery = try values.decode(Delivery.self, forKey: .delivery)
            security = try values.decode(Security.self, forKey: .security)
            kind = try values.decode(Kind.self, forKey: .kind)
            remoteAttachmentURL = try values.decodeIfPresent(String.self, forKey: .remoteAttachmentURL)
            localFilename = try values.decodeIfPresent(String.self, forKey: .localFilename)
            mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
            duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration)
            byteCount = try values.decodeIfPresent(Int.self, forKey: .byteCount)
            encryptionFingerprint = try values.decodeIfPresent(
                String.self,
                forKey: .encryptionFingerprint
            )
            editedAt = try values.decodeIfPresent(Date.self, forKey: .editedAt)
            replyToID = try values.decodeIfPresent(String.self, forKey: .replyToID)
            replyToJID = try values.decodeIfPresent(String.self, forKey: .replyToJID)
            replyPreview = try values.decodeIfPresent(String.self, forKey: .replyPreview)
            forwardedFrom = try values.decodeIfPresent(String.self, forKey: .forwardedFrom)
            retractedAt = try values.decodeIfPresent(Date.self, forKey: .retractedAt)
            originID = try values.decodeIfPresent(String.self, forKey: .originID)
            stanzaID = try values.decodeIfPresent(String.self, forKey: .stanzaID)
            senderDisplayName = try values.decodeIfPresent(String.self, forKey: .senderDisplayName)
            isGroupMessage = try values.decodeIfPresent(Bool.self, forKey: .isGroupMessage) ?? false
            callHistory = try values.decodeIfPresent(CallHistoryMetadata.self, forKey: .callHistory)
            reactions = try values.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
        }
    }

    struct Snapshot: Codable {
        static let currentSchemaVersion = 6

        var schemaVersion: Int
        var conversations: [LegacyConversation]
        var messages: [LegacyMessage]
        var locallyDeletedMessageIDs: Set<String>
        var rosterContactJIDs: Set<String>
        var lastSuccessfulMAMSync: Date?
        var lastSuccessfulMAMCursor: String?
        var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]

        init(
            conversations: [LegacyConversation],
            messages: [LegacyMessage],
            locallyDeletedMessageIDs: Set<String> = [],
            rosterContactJIDs: Set<String> = [],
            lastSuccessfulMAMSync: Date? = nil,
            lastSuccessfulMAMCursor: String? = nil,
            mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint] = [:]
        ) {
            self.schemaVersion = Self.currentSchemaVersion
            self.conversations = conversations
            self.messages = messages
            self.locallyDeletedMessageIDs = locallyDeletedMessageIDs
            self.rosterContactJIDs = rosterContactJIDs
            self.lastSuccessfulMAMSync = lastSuccessfulMAMSync
            self.lastSuccessfulMAMCursor = lastSuccessfulMAMCursor
            self.mamCheckpoints = mamCheckpoints
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case conversations
            case messages
            case locallyDeletedMessageIDs
            case rosterContactJIDs
            case lastSuccessfulMAMSync
            case lastSuccessfulMAMCursor
            case mamCheckpoints
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            conversations = try values.decode([LegacyConversation].self, forKey: .conversations)
            messages = try values.decode([LegacyMessage].self, forKey: .messages)
            locallyDeletedMessageIDs = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .locallyDeletedMessageIDs
            ) ?? []
            rosterContactJIDs = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .rosterContactJIDs
            ) ?? []
            lastSuccessfulMAMSync = try values.decodeIfPresent(
                Date.self,
                forKey: .lastSuccessfulMAMSync
            )
            lastSuccessfulMAMCursor = ArchiveSyncCheckpoint.normalizedCursor(
                try values.decodeIfPresent(String.self, forKey: .lastSuccessfulMAMCursor)
            )
            mamCheckpoints = try values.decodeIfPresent(
                [MAMArchiveKey: MAMArchiveCheckpoint].self,
                forKey: .mamCheckpoints
            ) ?? [:]
        }
    }

    struct Imported {
        let conversations: [Conversation]
        let messages: [ChatMessage]
        let locallyDeletedMessageIDs: [String]
        let rosterContactJIDs: [String]
        let lastSuccessfulMAMSync: Date?
        let lastSuccessfulMAMCursor: String?
        let mamCheckpoints: [MAMCheckpointEntry]
    }

    static func importIfNeeded(from url: URL) throws -> Imported? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(Snapshot.self, from: data)

        let conversations = snapshot.conversations.map { legacy -> Conversation in
            let conversation = Conversation(
                jid: legacy.jid,
                displayName: legacy.displayName,
                lastMessage: legacy.lastMessage,
                lastActivity: legacy.lastActivity,
                unreadCount: legacy.unreadCount,
                isOnline: legacy.isOnline,
                isPinned: legacy.isPinned,
                encryptionPreference: legacy.encryptionPreference,
                kind: legacy.kind == .group ? .group : .direct,
                groupNickname: legacy.groupNickname,
                isGroupJoined: legacy.isGroupJoined,
                shouldAutojoin: legacy.shouldAutojoin,
                occupantCount: legacy.occupantCount,
                invitedBy: legacy.invitedBy
            )
            return conversation
        }

        let conversationByJID = Dictionary(
            conversations.map { ($0.jid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let messages = snapshot.messages.map { legacy -> ChatMessage in
            let message = ChatMessage(
                id: legacy.id,
                conversationID: legacy.conversationID,
                senderJID: legacy.senderJID,
                body: legacy.body,
                timestamp: legacy.timestamp,
                direction: legacy.direction == .outgoing ? .outgoing : .incoming,
                delivery: ChatMessage.Delivery(rawValue: legacy.delivery.rawValue) ?? .sent,
                security: ChatMessage.Security(rawValue: legacy.security.rawValue) ?? .plaintext,
                kind: ChatMessage.Kind(rawValue: legacy.kind.rawValue) ?? .text,
                remoteAttachmentURL: legacy.remoteAttachmentURL,
                localFilename: legacy.localFilename,
                mimeType: legacy.mimeType,
                duration: legacy.duration,
                byteCount: legacy.byteCount,
                encryptionFingerprint: legacy.encryptionFingerprint,
                editedAt: legacy.editedAt,
                replyToID: legacy.replyToID,
                replyToJID: legacy.replyToJID,
                replyPreview: legacy.replyPreview,
                forwardedFrom: legacy.forwardedFrom,
                retractedAt: legacy.retractedAt,
                originID: legacy.originID,
                stanzaID: legacy.stanzaID,
                senderDisplayName: legacy.senderDisplayName,
                isGroupMessage: legacy.isGroupMessage,
                callHistory: legacy.callHistory,
                reactions: legacy.reactions
            )
            message.conversation = conversationByJID[legacy.conversationID.lowercased()]
            return message
        }

        return Imported(
            conversations: conversations,
            messages: messages,
            locallyDeletedMessageIDs: Array(snapshot.locallyDeletedMessageIDs),
            rosterContactJIDs: Array(snapshot.rosterContactJIDs),
            lastSuccessfulMAMSync: snapshot.lastSuccessfulMAMSync,
            lastSuccessfulMAMCursor: snapshot.lastSuccessfulMAMCursor,
            mamCheckpoints: snapshot.mamCheckpoints.map {
                MAMCheckpointEntry(key: $0.key, checkpoint: $0.value)
            }
        )
    }
}

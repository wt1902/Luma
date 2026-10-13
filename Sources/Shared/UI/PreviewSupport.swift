import Foundation
import SwiftData
import SwiftUI

/// Shared fixtures for SwiftUI previews.
///
/// Building an `AppModel` wires up the XMPP service, the WebRTC call engine
/// and the keychain-backed stores, so previews share one instance instead of
/// rebuilding it per canvas (the model skips account bootstrap inside the
/// preview host). SwiftData screens share one stable in-memory container and
/// seeded context so `@Query`-backed lists render sample data without
/// touching the real archive or re-fetching on every body evaluation.
enum PreviewSupport {
    /// Single shared model: no account, no network traffic, connection is
    /// "disconnected" — every screen renders in its resting state.
    static let model: AppModel = MainActor.assumeIsolated { AppModel() }

    // MARK: - SwiftData

    /// Shared in-memory container for `@Query`-backed previews. One stable
    /// container/context pair keeps SwiftUI list diffing from seeing a
    /// brand-new fetch result on every body evaluation.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Conversation.self, ChatMessage.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create the preview container: \(error)")
        }
    }()

    /// Seeded context: two direct chats, one group and a short Alice thread.
    @MainActor
    static let previewContext: ModelContext = {
        let context = container.mainContext

        let alice = conversation(
            jid: "alice@example.org",
            displayName: "Алиса",
            lastMessage: "Договорились 👌",
            lastActivity: Date().addingTimeInterval(-120),
            unreadCount: 2,
            isOnline: true
        )
        let bob = conversation(
            jid: "bob@example.org",
            displayName: "Боб",
            lastMessage: "Файл: отчёт.pdf",
            lastActivity: Date().addingTimeInterval(-3_600)
        )
        let team = conversation(
            jid: "team@conference.example.org",
            displayName: "Команда Luma",
            lastMessage: "Иван: созвон в 15:00",
            lastActivity: Date().addingTimeInterval(-86_400),
            unreadCount: 5,
            kind: .group,
            isGroupJoined: true,
            occupantCount: 7
        )
        context.insert(alice)
        context.insert(bob)
        context.insert(team)

        let aliceJID = alice.jid
        context.insert(
            message(
                conversationID: aliceJID,
                senderJID: aliceJID,
                body: "Привет! Как дела?",
                timestamp: Date().addingTimeInterval(-600),
                direction: .incoming,
                delivery: .delivered
            )
        )
        context.insert(
            message(
                conversationID: aliceJID,
                senderJID: "me@example.org",
                body: "Отлично! Созвонимся вечером?",
                timestamp: Date().addingTimeInterval(-420),
                direction: .outgoing,
                delivery: .sent
            )
        )
        context.insert(
            message(
                conversationID: aliceJID,
                senderJID: aliceJID,
                body: "Договорились 👌",
                timestamp: Date().addingTimeInterval(-60),
                direction: .incoming,
                delivery: .delivered
            )
        )
        return context
    }()

    // MARK: - Models

    static func conversation(
        jid: String = "alice@example.org",
        displayName: String? = nil,
        lastMessage: String = "",
        lastActivity: Date = .distantPast,
        unreadCount: Int = 0,
        isOnline: Bool = false,
        isPinned: Bool = false,
        encryptionPreference: EncryptionPreference = .inheritGlobal,
        kind: Conversation.Kind = .direct,
        groupNickname: String? = nil,
        isGroupJoined: Bool = false,
        shouldAutojoin: Bool = false,
        occupantCount: Int = 0,
        invitedBy: String? = nil
    ) -> Conversation {
        Conversation(
            jid: jid,
            displayName: displayName,
            lastMessage: lastMessage,
            lastActivity: lastActivity,
            unreadCount: unreadCount,
            isOnline: isOnline,
            isPinned: isPinned,
            encryptionPreference: encryptionPreference,
            kind: kind,
            groupNickname: groupNickname,
            isGroupJoined: isGroupJoined,
            shouldAutojoin: shouldAutojoin,
            occupantCount: occupantCount,
            invitedBy: invitedBy
        )
    }

    static func message(
        id: String = UUID().uuidString,
        conversationID: String = "alice@example.org",
        senderJID: String = "alice@example.org",
        body: String = "Привет! Как дела?",
        timestamp: Date = Date(),
        direction: ChatMessage.Direction = .incoming,
        delivery: ChatMessage.Delivery = .delivered,
        security: ChatMessage.Security = .omemo,
        kind: ChatMessage.Kind = .text,
        remoteAttachmentURL: String? = nil,
        localFilename: String? = nil,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        byteCount: Int? = nil,
        senderDisplayName: String? = nil,
        isGroupMessage: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationID: conversationID,
            senderJID: senderJID,
            body: body,
            timestamp: timestamp,
            direction: direction,
            delivery: delivery,
            security: security,
            kind: kind,
            remoteAttachmentURL: remoteAttachmentURL,
            localFilename: localFilename,
            mimeType: mimeType,
            duration: duration,
            byteCount: byteCount,
            senderDisplayName: senderDisplayName,
            isGroupMessage: isGroupMessage
        )
    }

    static func photoMessage(
        body: String = "Фото с прогулки",
        filename: String = "IMG_1234.jpg",
        byteCount: Int = 2_420_112
    ) -> ChatMessage {
        message(
            body: body,
            kind: .photo,
            localFilename: filename,
            mimeType: "image/jpeg",
            byteCount: byteCount
        )
    }

    static func videoMessage(
        body: String = "Видео с концерта",
        filename: String = "IMG_5678.mov",
        duration: TimeInterval = 42,
        byteCount: Int = 18_330_240
    ) -> ChatMessage {
        message(
            body: body,
            kind: .video,
            localFilename: filename,
            mimeType: "video/quicktime",
            duration: duration,
            byteCount: byteCount
        )
    }

    static func videoNoteMessage(
        body: String = "",
        duration: TimeInterval = 12
    ) -> ChatMessage {
        message(
            body: body,
            kind: .videoNote,
            mimeType: "video/mp4",
            duration: duration,
            byteCount: 1_840_000
        )
    }

    static func voiceMessage(
        body: String = "",
        duration: TimeInterval = 9
    ) -> ChatMessage {
        message(
            body: body,
            kind: .voice,
            mimeType: "audio/m4a",
            duration: duration,
            byteCount: 180_000
        )
    }

    static func callSnapshot(
        peerJID: String = "alice@example.org",
        direction: CallDirection = .incoming,
        media: Set<CallMedia> = [.video],
        phase: CallPhase = .ringing,
        isMuted: Bool = false,
        isCameraEnabled: Bool = true,
        isSpeakerEnabled: Bool = true
    ) -> CallSnapshot {
        CallSnapshot(
            id: UUID(),
            peerJID: peerJID,
            direction: direction,
            media: media,
            phase: phase,
            connectedAt: phase == .connected ? Date().addingTimeInterval(-75) : nil,
            isMuted: isMuted,
            isCameraEnabled: isCameraEnabled,
            isSpeakerEnabled: isSpeakerEnabled,
            hasLocalVideo: media.contains(.video),
            hasRemoteVideo: media.contains(.video)
        )
    }

    static func drafts() -> [AttachmentDraft] {
        [
            AttachmentDraft(
                url: URL(fileURLWithPath: "/tmp/preview-photo.jpg"),
                filename: "IMG_1234.jpg",
                mimeType: "image/jpeg",
                kind: .photo,
                byteCount: 2_420_112
            ),
            AttachmentDraft(
                url: URL(fileURLWithPath: "/tmp/preview-video.mov"),
                filename: "IMG_5678.mov",
                mimeType: "video/quicktime",
                kind: .video,
                duration: 21,
                byteCount: 18_330_240
            ),
        ]
    }

    // MARK: - Composed scenes

    /// Populated chat screen: a conversation plus the seeded Alice thread so
    /// the `@Query`-driven timeline renders bubbles instead of an empty
    /// state.
    @MainActor
    static func chatPreview() -> some View {
        let conversation = conversation(
            jid: "alice@example.org",
            displayName: "Алиса",
            lastMessage: "Договорились 👌",
            lastActivity: Date().addingTimeInterval(-60),
            isOnline: true
        )
        return ChatView(model: model, conversation: conversation)
            .environment(\.modelContext, previewContext)
    }

    /// Main screen backed by the seeded in-memory context so the chat list
    /// shows conversations on both platforms.
    @MainActor
    static func mainPreview() -> some View {
        MainTabView(model: model)
            .environment(\.modelContext, previewContext)
    }
}

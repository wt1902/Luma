import Foundation

struct PhoneWatchSnapshot: Codable {
    struct Chat: Codable {
        let jid: String
        let name: String
        let unread: Int
        let messages: [Message]
    }

    struct Message: Codable, Identifiable {
        let id: String
        let body: String
        let timestamp: Date
        let outgoing: Bool
        let encrypted: Bool
    }

    let chats: [Chat]
}

/// Plain-value snapshots of the SwiftData models, taken on the main actor
/// before the background queue builds the watch payload. Reading @Model
/// properties off the main actor crashes with EXC_BAD_ACCESS.
private struct PhoneWatchChatData {
    let jid: String
    let name: String
    let unread: Int
}

private struct PhoneWatchMessageData {
    let id: String
    let conversationID: String
    let body: String
    let timestamp: Date
    let outgoing: Bool
    let encrypted: Bool
}

struct WatchVoiceMessage: Sendable {
    let transferID: String
    let jid: String
    let filename: String
    let duration: TimeInterval?
    let data: Data

    var stableMessageID: String {
        "watch-\(transferID)"
    }
}

#if os(iOS) && canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity

final class PhoneWatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onReply: ((String, String) -> Void)?
    var onVoiceMessage: ((WatchVoiceMessage) -> Void)? {
        didSet { deliverPendingVoiceMessages() }
    }
    private let session: WCSession?
    private let snapshotQueue = DispatchQueue(
        label: "app.luma.watch-snapshot",
        qos: .utility
    )
    private var latestSnapshot: Data?
    private var pendingVoiceMessages: [WatchVoiceMessage] = []
    private var deliveredVoiceTransferIDs: Set<String> = []

    override init() {
        session =
            !RuntimeEnvironment.isRunningTests && WCSession.isSupported()
            ? .default
            : nil
        super.init()
        pendingVoiceMessages = Self.loadPersistedVoiceMessages()
        session?.delegate = self
        session?.activate()
    }

    @MainActor
    func update(conversations: [Conversation], messages: [ChatMessage]) {
        guard let session else { return }
        // SwiftData models must never be read off the main actor: snapshot
        // the fields the watch needs here, then hand plain values to the
        // background queue for the filtering, sorting and JSON encoding.
        let chats = conversations.map { conversation in
            PhoneWatchChatData(
                jid: conversation.jid,
                name: conversation.displayName,
                unread: conversation.unreadCount
            )
        }
        let entries = messages.map { message in
            PhoneWatchMessageData(
                id: message.clientID,
                conversationID: message.conversationID,
                body: message.previewText,
                timestamp: message.timestamp,
                outgoing: message.direction == .outgoing,
                encrypted: message.security == .omemo
            )
        }
        snapshotQueue.async { [weak self, weak session] in
            guard let self,
                  let session,
                  let data = Self.makeSnapshotData(chats: chats, entries: entries),
                  data != self.latestSnapshot else { return }
            self.latestSnapshot = data
            self.publishLatestSnapshot(using: session)
        }
    }

    private static func makeSnapshotData(
        chats: [PhoneWatchChatData],
        entries: [PhoneWatchMessageData]
    ) -> Data? {
        let visibleChats = Array(chats.prefix(20))
        let visibleChatIDs = Set(visibleChats.map(\.jid))
        var recentMessagesByChat: [String: [PhoneWatchMessageData]] = [:]

        // Keep a bounded, chronologically sorted window. MAM can append an old
        // overlapping stanza after a newer live message, so array order alone
        // cannot identify the latest messages reliably.
        for entry in entries where visibleChatIDs.contains(entry.conversationID) {
            var recent = recentMessagesByChat[entry.conversationID] ?? []
            let insertionIndex = Self.insertionIndex(for: entry, in: recent)
            recent.insert(entry, at: insertionIndex)
            if recent.count > 20 {
                recent.removeFirst(recent.count - 20)
            }
            recentMessagesByChat[entry.conversationID] = recent
        }

        let snapshotChats = visibleChats.map { chat in
            PhoneWatchSnapshot.Chat(
                jid: chat.jid,
                name: chat.name,
                unread: chat.unread,
                messages: (recentMessagesByChat[chat.jid] ?? []).map { entry in
                    PhoneWatchSnapshot.Message(
                        id: entry.id,
                        body: entry.body,
                        timestamp: entry.timestamp,
                        outgoing: entry.outgoing,
                        encrypted: entry.encrypted
                    )
                }
            )
        }
        return try? JSONEncoder.watchEncoder.encode(PhoneWatchSnapshot(chats: snapshotChats))
    }

    private static func insertionIndex(
        for entry: PhoneWatchMessageData,
        in sorted: [PhoneWatchMessageData]
    ) -> Int {
        var lowerBound = 0
        var upperBound = sorted.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let existing = sorted[middle]
            let existingComesFirst = existing.timestamp < entry.timestamp
                || (existing.timestamp == entry.timestamp && existing.id < entry.id)
            if existingComesFirst {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        snapshotQueue.async { [weak self, weak session] in
            guard let self, let session else { return }
            self.publishLatestSnapshot(using: session)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        consume(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        consume(userInfo)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata,
              metadata["action"] as? String == "voice",
              let transferID = metadata["transferID"] as? String,
              UUID(uuidString: transferID) != nil,
              let jid = metadata["jid"] as? String,
              !jid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            // WCSession owns this URL only for the duration of the callback.
            // Copy the bytes before handing the recording to the async upload
            // pipeline so the temporary file cannot disappear underneath it.
            let data = try Data(contentsOf: file.fileURL)
            guard !data.isEmpty else { throw WatchVoiceBridgeError.emptyRecording }
            let duration = (metadata["duration"] as? NSNumber)?.doubleValue
            let filename = (metadata["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? file.fileURL.lastPathComponent
            let message = WatchVoiceMessage(
                transferID: transferID,
                jid: jid,
                filename: filename,
                duration: duration,
                data: data
            )
            try Self.persistVoiceMessage(message)
            DispatchQueue.main.async { [weak self] in
                self?.deliverVoiceMessage(message)
            }
        } catch {
            reportVoiceResult(
                transferID: transferID,
                success: false,
                error: "iPhone не смог прочитать запись: \(error.localizedDescription)",
                jid: jid
            )
        }
    }

    func reportVoiceResult(
        transferID: String,
        success: Bool,
        error: String? = nil,
        jid explicitJID: String? = nil
    ) {
        guard let session else { return }
        let jid = explicitJID ?? Self.persistedVoiceJID(for: transferID)
        Self.removePersistedVoiceMessage(transferID: transferID)
        deliveredVoiceTransferIDs.remove(transferID)
        var payload: [String: Any] = [
            "action": "voiceResult",
            "transferID": transferID,
            "success": success
        ]
        if let jid, !jid.isEmpty {
            payload["jid"] = jid
        }
        if let error, !error.isEmpty {
            payload["error"] = error
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func consume(_ payload: [String: Any]) {
        guard payload["action"] as? String == "reply",
              let jid = payload["jid"] as? String,
              let text = payload["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onReply?(jid, text)
    }

    private func publishLatestSnapshot(using session: WCSession) {
        guard let latestSnapshot else { return }
        try? session.updateApplicationContext(["snapshot": latestSnapshot])
    }

    private func deliverVoiceMessage(_ message: WatchVoiceMessage) {
        if let onVoiceMessage {
            guard deliveredVoiceTransferIDs.insert(message.transferID).inserted else { return }
            onVoiceMessage(message)
        } else if !pendingVoiceMessages.contains(where: { $0.transferID == message.transferID }) {
            pendingVoiceMessages.append(message)
        }
    }

    private func deliverPendingVoiceMessages() {
        guard let onVoiceMessage, !pendingVoiceMessages.isEmpty else { return }
        let pending = pendingVoiceMessages
        pendingVoiceMessages.removeAll()
        for message in pending where deliveredVoiceTransferIDs.insert(message.transferID).inserted {
            onVoiceMessage(message)
        }
    }

    private static func persistVoiceMessage(_ message: WatchVoiceMessage) throws {
        let directory = try watchVoiceOutboxDirectory()
        let audioFilename = "\(message.transferID).m4a"
        let audioURL = directory.appendingPathComponent(audioFilename)
        let metadataURL = directory.appendingPathComponent("\(message.transferID).json")
        let stored = StoredWatchVoiceMessage(
            transferID: message.transferID,
            jid: message.jid,
            filename: message.filename,
            duration: message.duration,
            audioFilename: audioFilename,
            createdAt: Date()
        )

        do {
            try message.data.write(to: audioURL, options: [.atomic])
            try JSONEncoder().encode(stored).write(to: metadataURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: audioURL.path
            )
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: metadataURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: metadataURL)
            throw error
        }
    }

    private static func loadPersistedVoiceMessages() -> [WatchVoiceMessage] {
        guard let directory = try? watchVoiceOutboxDirectory() else { return [] }
        let metadataURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let expiration = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        return metadataURLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { metadataURL in
                guard let metadataData = try? Data(contentsOf: metadataURL),
                      let stored = try? JSONDecoder().decode(
                        StoredWatchVoiceMessage.self,
                        from: metadataData
                      ),
                      stored.createdAt >= expiration else {
                    removePersistedVoiceMessage(
                        transferID: metadataURL.deletingPathExtension().lastPathComponent
                    )
                    return nil
                }
                let audioURL = directory.appendingPathComponent(stored.audioFilename)
                guard let data = try? Data(contentsOf: audioURL), !data.isEmpty else {
                    removePersistedVoiceMessage(transferID: stored.transferID)
                    return nil
                }
                return WatchVoiceMessage(
                    transferID: stored.transferID,
                    jid: stored.jid,
                    filename: stored.filename,
                    duration: stored.duration,
                    data: data
                )
            }
            .sorted { $0.transferID < $1.transferID }
    }

    private static func persistedVoiceJID(for transferID: String) -> String? {
        guard let directory = try? watchVoiceOutboxDirectory(),
              let data = try? Data(contentsOf: directory.appendingPathComponent("\(transferID).json")),
              let stored = try? JSONDecoder().decode(StoredWatchVoiceMessage.self, from: data) else {
            return nil
        }
        return stored.jid
    }

    private static func removePersistedVoiceMessage(transferID: String) {
        guard UUID(uuidString: transferID) != nil,
              let directory = try? watchVoiceOutboxDirectory() else { return }
        let metadataURL = directory.appendingPathComponent("\(transferID).json")
        if let data = try? Data(contentsOf: metadataURL),
           let stored = try? JSONDecoder().decode(StoredWatchVoiceMessage.self, from: data) {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(stored.audioFilename)
            )
        } else {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent("\(transferID).m4a")
            )
        }
        try? FileManager.default.removeItem(at: metadataURL)
    }

    private static func watchVoiceOutboxDirectory() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Luma/WatchVoiceOutbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StoredWatchVoiceMessage: Codable {
    let transferID: String
    let jid: String
    let filename: String
    let duration: TimeInterval?
    let audioFilename: String
    let createdAt: Date
}

#else

final class PhoneWatchBridge {
    var onReply: ((String, String) -> Void)?
    var onVoiceMessage: ((WatchVoiceMessage) -> Void)?
    func update(conversations: [Conversation], messages: [ChatMessage]) {}
    func reportVoiceResult(transferID: String, success: Bool, error: String? = nil) {}
}

#endif

private extension JSONEncoder {
    static var watchEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private enum WatchVoiceBridgeError: LocalizedError {
    case emptyRecording

    var errorDescription: String? {
        "Файл голосового сообщения пуст."
    }
}

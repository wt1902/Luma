import Foundation
import SwiftData

/// SwiftData-backed replacement for the legacy JSON `ChatArchive`. Owns the
/// per-account `ModelContainer`/`ModelContext`, imports the old JSON snapshot
/// once, and exposes load/save/erase.
@MainActor
final class ArchiveStore {
    struct Loaded {
        var conversations: [Conversation]
        var messages: [ChatMessage]
        var locallyDeletedMessageIDs: Set<String>
        var rosterContactJIDs: Set<String>
        var lastSuccessfulMAMSync: Date?
        var lastSuccessfulMAMCursor: String?
        var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]
    }

    let container: ModelContainer
    let context: ModelContext
    private let accountJID: String
    private let storeURL: URL
    private let legacyJSONURL: URL
    private(set) var metadata: ArchiveMetadata?

    init(accountJID: String) throws {
        self.accountJID = accountJID
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Luma/Accounts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = Self.stableHash(accountJID)
        storeURL = directory.appendingPathComponent("\(hash).store")
        legacyJSONURL = directory.appendingPathComponent("\(hash).json")

        let schema = Schema([
            Conversation.self,
            ChatMessage.self,
            ArchiveMetadata.self,
        ])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        applyDataProtection()

        migrateLegacyJSONIfNeeded()
        purgeLocallyDeletedMessages()
    }

    func load() -> Loaded {
        let conversationSort = [SortDescriptor(\Conversation.lastActivity, order: .reverse)]
        let conversations = (try? context.fetch(FetchDescriptor<Conversation>(sortBy: conversationSort))) ?? []
        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []

        let metadata = fetchMetadata()
        let mamCheckpoints = Dictionary(
            metadata.mamCheckpoints.map { ($0.key, $0.checkpoint) },
            uniquingKeysWith: { first, _ in first }
        )

        return Loaded(
            conversations: conversations,
            messages: messages,
            locallyDeletedMessageIDs: Set(metadata.locallyDeletedMessageIDs),
            rosterContactJIDs: Set(metadata.rosterContactJIDs),
            lastSuccessfulMAMSync: metadata.lastSuccessfulMAMSync,
            lastSuccessfulMAMCursor: metadata.lastSuccessfulMAMCursor,
            mamCheckpoints: mamCheckpoints
        )
    }

    /// Persists the passed metadata plus all pending model mutations.
    func save(
        locallyDeletedMessageIDs: Set<String>,
        rosterContactJIDs: Set<String>,
        lastSuccessfulMAMSync: Date?,
        lastSuccessfulMAMCursor: String?,
        mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]
    ) throws {
        let metadata = fetchMetadata()
        metadata.locallyDeletedMessageIDs = Array(locallyDeletedMessageIDs)
        metadata.rosterContactJIDs = Array(rosterContactJIDs)
        metadata.lastSuccessfulMAMSync = lastSuccessfulMAMSync
        metadata.lastSuccessfulMAMCursor = ArchiveSyncCheckpoint.normalizedCursor(lastSuccessfulMAMCursor)
        metadata.mamCheckpoints = mamCheckpoints.map {
            MAMCheckpointEntry(key: $0.key, checkpoint: $0.value)
        }
        try context.save()
        applyDataProtection()
    }

    func erase() throws {
        try context.delete(model: Conversation.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: ArchiveMetadata.self)
        try context.save()
    }

    private func fetchMetadata() -> ArchiveMetadata {
        if let metadata { return metadata }
        let existing = try? context.fetch(FetchDescriptor<ArchiveMetadata>()).first
        let metadata = existing ?? ArchiveMetadata(accountJID: accountJID)
        context.insert(metadata)
        self.metadata = metadata
        return metadata
    }

    private func migrateLegacyJSONIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyJSONURL.path) else { return }
        guard let imported = try? LegacyArchiveImporter.importIfNeeded(from: legacyJSONURL) else {
            return
        }
        for conversation in imported.conversations {
            context.insert(conversation)
        }
        for message in imported.messages {
            context.insert(message)
        }
        let metadata = fetchMetadata()
        metadata.locallyDeletedMessageIDs = imported.locallyDeletedMessageIDs
        metadata.rosterContactJIDs = imported.rosterContactJIDs
        metadata.lastSuccessfulMAMSync = imported.lastSuccessfulMAMSync
        metadata.lastSuccessfulMAMCursor = imported.lastSuccessfulMAMCursor
        metadata.mamCheckpoints = imported.mamCheckpoints
        do {
            try context.save()
        } catch {
            // The imported rows stay pending in memory so this session keeps
            // the history, but the legacy JSON remains on disk as the only
            // durable copy until a save actually succeeds.
            return
        }
        applyDataProtection()
        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    /// Removes rows that older builds only marked as locally deleted (the
    /// legacy snapshot filtered them at load time). `@Query`-based views read
    /// the store directly, so these rows must physically disappear.
    func purgeLocallyDeletedMessages() {
        let metadata = fetchMetadata()
        let deletedKeys = Set(metadata.locallyDeletedMessageIDs)
        guard !deletedKeys.isEmpty else { return }
        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
        var removedAny = false
        for message in messages {
            let key = Self.deletionKey(
                messageID: message.clientID,
                conversationID: message.conversationID
            )
            guard deletedKeys.contains(key) else { continue }
            context.delete(message)
            removedAny = true
        }
        if removedAny {
            try? context.save()
            applyDataProtection()
        }
    }

    /// Key format shared with `AppModel.localDeletionKey`:
    /// `<conversationID>\u{1F}<messageID>`.
    static func deletionKey(messageID: String, conversationID: String) -> String {
        conversationID.lowercased() + "\u{1F}" + messageID
    }

    private func applyDataProtection() {
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: storeURL.path
        )
#endif
    }

    static func stableHash(_ value: String) -> String {
        let hash = value.lowercased().utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}

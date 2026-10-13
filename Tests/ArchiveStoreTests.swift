import SwiftData
import XCTest
@testable import Luma

@MainActor
final class ArchiveStoreTests: XCTestCase {
    func testStoreRoundTrip() async throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let store = try ArchiveStore(accountJID: jid)
        defer { try? store.erase() }

        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let message = ChatMessage(
            conversationID: conversation.jid,
            senderJID: jid,
            body: "Encrypted hello",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            direction: .outgoing,
            delivery: .sent,
            security: .omemo
        )
        store.context.insert(conversation)
        store.context.insert(message)

        try store.save(
            locallyDeletedMessageIDs: ["deleted-message-id"],
            rosterContactJIDs: [conversation.jid],
            lastSuccessfulMAMSync: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulMAMCursor: "mam-cursor-42",
            mamCheckpoints: [:]
        )

        let loaded = store.load()
        XCTAssertEqual(loaded.conversations.map(\.jid), [conversation.jid])
        XCTAssertEqual(loaded.messages.map(\.clientID), [message.clientID])
        XCTAssertEqual(loaded.locallyDeletedMessageIDs, Set(["deleted-message-id"]))
        XCTAssertEqual(loaded.rosterContactJIDs, Set([conversation.jid]))
        XCTAssertEqual(
            loaded.lastSuccessfulMAMSync,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(loaded.lastSuccessfulMAMCursor, "mam-cursor-42")
    }

    func testLegacyImportMapsConversationAndMessage() throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let legacy = LegacyArchiveImporter.Snapshot(
            conversations: [
                LegacyArchiveImporter.LegacyConversation(
                    id: "bob@example.org",
                    jid: "bob@example.org",
                    displayName: "Bob",
                    lastMessage: "",
                    lastActivity: .distantPast,
                    unreadCount: 0,
                    isOnline: false,
                    isPinned: false,
                    encryptionPreference: .inheritGlobal,
                    kind: .direct,
                    groupNickname: nil,
                    isGroupJoined: false,
                    shouldAutojoin: false,
                    occupantCount: 0,
                    invitedBy: nil
                )
            ],
            messages: [
                LegacyArchiveImporter.LegacyMessage(
                    id: "msg-1",
                    conversationID: "bob@example.org",
                    senderJID: jid,
                    body: "Hello",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    direction: .outgoing,
                    delivery: .sent,
                    security: .omemo,
                    kind: .text
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(legacy)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let imported = try LegacyArchiveImporter.importIfNeeded(from: url)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.conversations.map(\.jid), ["bob@example.org"])
        XCTAssertEqual(imported?.messages.map(\.clientID), ["msg-1"])
        XCTAssertEqual(imported?.messages.first?.conversation?.jid, "bob@example.org")
    }

    func testLegacyImportToleratesMissingOptionalFields() throws {
        // Snapshots written by older schema versions lack fields that were
        // added later (reactions, isGroupMessage, rosterContactJIDs, ...).
        // The importer must decode them with defaults, exactly like the
        // removed ChatArchive did.
        let raw: [String: Any] = [
            "schemaVersion": 2,
            "conversations": [
                [
                    "id": "bob@example.org",
                    "jid": "bob@example.org",
                    "displayName": "Bob",
                    "lastMessage": "",
                    "lastActivity": 1_700_000_000_000.0,
                    "unreadCount": 0,
                    "isOnline": false,
                    "isPinned": false,
                ]
            ],
            "messages": [
                [
                    "id": "msg-1",
                    "conversationID": "bob@example.org",
                    "senderJID": "alice@example.org",
                    "body": "Hello",
                    "timestamp": 1_700_000_000_000.0,
                    "direction": "outgoing",
                    "delivery": "sent",
                    "security": "omemo",
                    "kind": "text",
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let imported = try LegacyArchiveImporter.importIfNeeded(from: url)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.conversations.map(\.jid), ["bob@example.org"])
        XCTAssertEqual(imported?.conversations.first?.kind, .direct)
        XCTAssertEqual(imported?.conversations.first?.isGroupJoined, false)
        XCTAssertEqual(imported?.messages.map(\.clientID), ["msg-1"])
        XCTAssertEqual(imported?.messages.first?.isGroupMessage, false)
        XCTAssertEqual(imported?.messages.first?.reactions ?? [], [])
        XCTAssertEqual(imported?.rosterContactJIDs ?? [], [])
        XCTAssertEqual(imported?.mamCheckpoints ?? [], [])
        XCTAssertNil(imported?.lastSuccessfulMAMSync)
    }

    func testLocallyDeletedRowsArePurgedFromTheStore() throws {
        // @Query views read the store directly, so messages that were only
        // marked as locally deleted must be physically removed on open.
        let jid = "test-\(UUID().uuidString)@example.org"
        let store = try ArchiveStore(accountJID: jid)
        defer { try? store.erase() }

        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let message = ChatMessage(
            conversationID: conversation.jid,
            senderJID: jid,
            body: "Will be deleted",
            direction: .outgoing,
            delivery: .sent,
            security: .omemo
        )
        store.context.insert(conversation)
        store.context.insert(message)
        let deletionKey = ArchiveStore.deletionKey(
            messageID: message.clientID,
            conversationID: conversation.jid
        )
        try store.save(
            locallyDeletedMessageIDs: [deletionKey],
            rosterContactJIDs: [],
            lastSuccessfulMAMSync: nil,
            lastSuccessfulMAMCursor: nil,
            mamCheckpoints: [:]
        )

        store.purgeLocallyDeletedMessages()
        let loaded = store.load()
        XCTAssertTrue(loaded.messages.isEmpty)
        XCTAssertEqual(loaded.locallyDeletedMessageIDs, Set([deletionKey]))
    }

    func testCorruptLegacyJSONIsKeptForRetry() throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Luma/Accounts", isDirectory: true)
        let legacyURL = directory.appendingPathComponent("\(ArchiveStore.stableHash(jid)).json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: legacyURL)
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let store = try ArchiveStore(accountJID: jid)
        defer { try? store.erase() }
        XCTAssertTrue(store.load().conversations.isEmpty)
        // The unreadable snapshot must stay on disk instead of being deleted
        // together with the user's history.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }
}

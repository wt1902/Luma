import Foundation
import XCTest
@testable import Luma

final class MessageInteractionTests: XCTestCase {
    func testReplyMetadataIsStored() {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Ответ",
            direction: .outgoing,
            delivery: .sent,
            security: .omemo,
            replyToID: "original-id",
            replyToJID: "bob@example.org",
            replyPreview: "Исходный текст"
        )

        XCTAssertEqual(message.replyToID, "original-id")
        XCTAssertEqual(message.replyToJID, "bob@example.org")
        XCTAssertEqual(message.replyPreview, "Исходный текст")
    }

    func testRetractedMessageCannotBeEditedRepliedOrForwarded() {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Удалено",
            direction: .outgoing,
            delivery: .delivered,
            security: .omemo,
            retractedAt: Date()
        )

        XCTAssertFalse(message.canBeEdited)
        XCTAssertFalse(message.canBeRepliedTo)
        XCTAssertFalse(message.canBeForwarded)
        XCTAssertFalse(message.canBeRetracted)
        XCTAssertEqual(message.previewText, "🚫 Сообщение удалено")
    }

    func testGroupReplyRequiresRoomAssignedStanzaID() {
        var message = ChatMessage(
            conversationID: "team@conference.example.org",
            senderJID: "team@conference.example.org/alice",
            body: "Сообщение группы",
            direction: .incoming,
            delivery: .delivered,
            security: .omemo,
            senderDisplayName: "Alice",
            isGroupMessage: true
        )

        XCTAssertFalse(message.canBeRepliedTo)
        message.stanzaID = "room-stable-id"
        XCTAssertTrue(message.canBeRepliedTo)
        XCTAssertEqual(message.replyIdentifier, "room-stable-id")
        XCTAssertEqual(message.security, .omemo)
        XCTAssertFalse(message.canBeEdited)
        XCTAssertFalse(message.canBeRetracted)
    }

    func testCompletedVideoCallHistoryShowsMetadata() {
        let metadata = CallHistoryMetadata(isVideo: true, outcome: .completed)
        let message = ChatMessage(
            id: "call-alice-123",
            conversationID: "alice@example.org",
            senderJID: "me@example.org",
            body: "Видеозвонок",
            direction: .outgoing,
            delivery: .sent,
            security: .plaintext,
            kind: .system,
            duration: 65,
            callHistory: metadata
        )

        XCTAssertEqual(message.callHistory, metadata)
        XCTAssertEqual(message.callTitle, "Исходящий видеозвонок")
        XCTAssertEqual(message.callSubtitle, "Длительность 1:05")
        XCTAssertEqual(message.previewText, "🎥 Исходящий видеозвонок")
        XCTAssertFalse(message.canBeRepliedTo)
        XCTAssertFalse(message.canBeForwarded)
    }
}

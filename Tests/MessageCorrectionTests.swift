import Foundation
import XCTest
@testable import Luma

final class MessageCorrectionTests: XCTestCase {
    func testOnlyDeliveredOrSentOutgoingTextCanBeEdited() {
        func make(
            direction: ChatMessage.Direction = .outgoing,
            delivery: ChatMessage.Delivery = .sent,
            kind: ChatMessage.Kind = .text,
            retractedAt: Date? = nil
        ) -> ChatMessage {
            ChatMessage(
                conversationID: "bob@example.org",
                senderJID: "alice@example.org",
                body: "До исправления",
                direction: direction,
                delivery: delivery,
                security: .omemo,
                kind: kind,
                retractedAt: retractedAt
            )
        }

        XCTAssertTrue(make().canBeEdited)
        XCTAssertFalse(make(direction: .incoming).canBeEdited)
        XCTAssertFalse(make(kind: .attachment).canBeEdited)
        XCTAssertFalse(make(delivery: .failed).canBeEdited)
        XCTAssertFalse(make(retractedAt: Date()).canBeEdited)
    }

    func testEditedTimestampIsStored() {
        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "После исправления",
            direction: .outgoing,
            delivery: .delivered,
            security: .plaintext,
            editedAt: editedAt
        )

        XCTAssertEqual(message.editedAt, editedAt)
    }
}

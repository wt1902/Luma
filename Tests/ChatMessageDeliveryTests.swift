import XCTest
@testable import Luma

final class ChatMessageDeliveryTests: XCTestCase {
    func testMergeKeepsTheStrongestState() {
        XCTAssertEqual(ChatMessage.Delivery.sent.merged(with: .sending), .sent)
        XCTAssertEqual(ChatMessage.Delivery.sending.merged(with: .sent), .sent)
        XCTAssertEqual(ChatMessage.Delivery.sent.merged(with: .delivered), .delivered)
        XCTAssertEqual(ChatMessage.Delivery.delivered.merged(with: .read), .read)
        XCTAssertEqual(ChatMessage.Delivery.read.merged(with: .sent), .read)
        XCTAssertEqual(ChatMessage.Delivery.read.merged(with: .delivered), .read)
    }

    func testMAMReplayNeverDowngradesReadState() {
        // The archived copy of an outgoing message carries `.sent`; the local
        // copy that received the peer's displayed marker must stay `.read`.
        XCTAssertEqual(ChatMessage.Delivery.read.merged(with: .sent), .read)
        XCTAssertEqual(ChatMessage.Delivery.delivered.merged(with: .sent), .delivered)
    }

    func testFailedIsSticky() {
        XCTAssertEqual(ChatMessage.Delivery.failed.merged(with: .sent), .failed)
        XCTAssertEqual(ChatMessage.Delivery.sent.merged(with: .failed), .failed)
    }

    func testReadMessagesRemainEditableAndRetractable() {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "привет",
            direction: .outgoing,
            delivery: .read,
            security: .plaintext
        )
        XCTAssertTrue(message.canBeEdited)
        XCTAssertTrue(message.canBeRetracted)
    }
}

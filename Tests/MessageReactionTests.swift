import XCTest
@testable import Luma

final class MessageReactionTests: XCTestCase {
    func testReactionUpdateKeepsOneCopyOfEachEmoji() {
        XCTAssertEqual(
            MessageReactionPolicy.sanitized(["👍", " 👍 ", "❤️", "a", "not emoji"]),
            ["👍", "❤️"]
        )
    }

    func testSummariesCountSendersAndMarkOwnReaction() {
        let reactions = [
            MessageReaction(senderJID: "me@example.org/device", emojis: ["👍", "❤️"]),
            MessageReaction(senderJID: "you@example.org", emojis: ["👍"])
        ]
        let summaries = MessageReactionPolicy.summaries(
            reactions: reactions,
            ownJID: "me@example.org"
        )
        XCTAssertEqual(
            summaries.first(where: { $0.emoji == "👍" }),
            MessageReactionSummary(emoji: "👍", count: 2, includesOwnReaction: true)
        )
        XCTAssertEqual(
            summaries.first(where: { $0.emoji == "❤️" }),
            MessageReactionSummary(emoji: "❤️", count: 1, includesOwnReaction: true)
        )
    }
}

import Foundation
import XCTest
@testable import Luma

final class GroupConversationTests: XCTestCase {
    func testGroupConversationProperties() {
        let conversation = Conversation(
            jid: "team@conference.example.org",
            displayName: "Команда",
            encryptionPreference: .disabled,
            kind: .group,
            groupNickname: "Alice",
            isGroupJoined: true,
            shouldAutojoin: true,
            occupantCount: 4,
            invitedBy: "bob@example.org"
        )

        XCTAssertTrue(conversation.isGroup)
        XCTAssertEqual(conversation.groupNickname, "Alice")
        XCTAssertEqual(conversation.occupantCount, 4)
        XCTAssertEqual(conversation.invitedBy, "bob@example.org")
        XCTAssertEqual(conversation.encryptionPreference, .disabled)
    }

    func testNewGroupInheritsGlobalEncryptionByDefault() {
        let conversation = Conversation(
            jid: "team@conference.example.org",
            kind: .group
        )

        XCTAssertEqual(conversation.encryptionPreference, .inheritGlobal)
        XCTAssertTrue(conversation.isGroup)
    }
}

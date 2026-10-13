import Foundation
import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    let imageData: Data?
    let isEncrypted: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(conversation: conversation, imageData: imageData)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if conversation.lastActivity != .distantPast {
                        Text(conversation.lastActivity, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 7) {
                    if conversation.isGroup {
                        Image(systemName: "person.3.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !conversation.lastMessage.isEmpty {
                        Image(systemName: isEncrypted ? "lock.fill" : "lock.open")
                            .font(.caption2)
                            .foregroundStyle(isEncrypted ? Color.secondary : Color.orange)
                    }
                    Text(conversation.lastMessage.isEmpty ? conversation.jid : conversation.lastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if conversation.isGroup, conversation.occupantCount > 0 {
                        Text("\(conversation.occupantCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if conversation.unreadCount > 0 {
                        Text("\(min(conversation.unreadCount, 99))")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint, in: Capsule())
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

#Preview("Прямой чат") {
    ConversationRow(
        conversation: PreviewSupport.conversation(
            displayName: "Алиса",
            lastMessage: "Привет! Как дела?",
            lastActivity: Date().addingTimeInterval(-120),
            unreadCount: 2,
            isOnline: true
        ),
        imageData: nil,
        isEncrypted: true
    )
    .padding()
}

#Preview("Групповой чат") {
    ConversationRow(
        conversation: PreviewSupport.conversation(
            jid: "team@conference.example.org",
            displayName: "Команда Luma",
            lastMessage: "Иван: созвон в 15:00",
            lastActivity: Date().addingTimeInterval(-3_600),
            unreadCount: 5,
            kind: .group,
            isGroupJoined: true,
            occupantCount: 7
        ),
        imageData: nil,
        isEncrypted: true
    )
    .padding()
}

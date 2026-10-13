import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AvatarView: View {
    let conversation: Conversation
    var imageData: Data?
    var size: CGFloat = 50

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())

            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(Circle().stroke(.background, lineWidth: 2.5))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var avatarContent: some View {
#if os(iOS)
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
#elseif os(macOS)
        if let imageData, let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
#endif
    }

    private var fallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [baseColor, baseColor.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: size * 0.31, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(conversation.initials)
                        .font(.system(size: size * 0.35, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
    }

    private var isActive: Bool {
        conversation.isGroup ? conversation.isGroupJoined : conversation.isOnline
    }

    private var accessibilityText: String {
        if conversation.isGroup {
            return "\(conversation.displayName), \(conversation.isGroupJoined ? "подключено" : "не подключено")"
        }
        return "\(conversation.displayName), \(conversation.isOnline ? "в сети" : "не в сети")"
    }

    private var baseColor: Color {
        Color(
            hue: Double(conversation.colorSeed % 360) / 360,
            saturation: 0.68,
            brightness: 0.88
        )
    }
}

#Preview("Контакт") {
    AvatarView(
        conversation: PreviewSupport.conversation(displayName: "Алиса", isOnline: true)
    )
}

#Preview("Группа") {
    AvatarView(
        conversation: PreviewSupport.conversation(
            jid: "team@conference.example.org",
            displayName: "Команда Luma",
            kind: .group,
            isGroupJoined: true,
            occupantCount: 7
        )
    )
}

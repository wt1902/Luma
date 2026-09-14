import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// iMessage-style focus mode for one source message and its reply thread.
@MainActor
struct ReplyThreadOverlay: View {
    @ObservedObject var model: AppModel
    let rootMessage: ChatMessage
    let replies: [ChatMessage]
    let selectedReplyID: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                Color.black
                    .opacity(colorScheme == .dark ? 0.72 : 0.62)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            Text(
                                rootMessage.timestamp,
                                format: .dateTime
                                    .weekday(.abbreviated)
                                    .month(.abbreviated)
                                    .day()
                                    .hour()
                                    .minute()
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.56))
                            .padding(.bottom, 2)

                            threadContent(
                                maximumBubbleWidth: min(520, geometry.size.width * 0.76)
                            )
                        }
                        .frame(maxWidth: min(760, geometry.size.width))
                        .padding(.horizontal, 18)
                        .padding(.top, max(58, geometry.safeAreaInsets.top + 30))
                        .padding(.bottom, max(34, geometry.safeAreaInsets.bottom + 20))
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        isVisible = true
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.28)) {
                                proxy.scrollTo(selectedReplyID, anchor: .center)
                            }
                        }
                    }
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(7)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .background(.clear)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Закрыть ветку ответов")
                .padding(.top, max(12, geometry.safeAreaInsets.top + 6))
                .padding(.trailing, 14)
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.985)
            .animation(.easeOut(duration: 0.22), value: isVisible)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func threadContent(maximumBubbleWidth: CGFloat) -> some View {
        let showsBracket = replies.count > 1
        let bracketOnLeadingEdge = rootMessage.direction == .outgoing

        return VStack(spacing: 9) {
            ReplyThreadMessageRow(
                model: model,
                message: rootMessage,
                maximumBubbleWidth: maximumBubbleWidth,
                isSelected: false,
                showsDeliveryStatus: false
            )
            .id(rootMessage.id)

            if showsBracket {
                replyCountRow
            }

            ForEach(replies) { reply in
                ReplyThreadMessageRow(
                    model: model,
                    message: reply,
                    maximumBubbleWidth: maximumBubbleWidth,
                    isSelected: reply.clientID == selectedReplyID,
                    showsDeliveryStatus: reply.clientID == selectedReplyID
                )
                .id(reply.clientID)
            }
        }
        .padding(.leading, showsBracket && bracketOnLeadingEdge ? 43 : 0)
        .padding(.trailing, showsBracket && !bracketOnLeadingEdge ? 43 : 0)
        .overlay(
            alignment: bracketOnLeadingEdge ? .leading : .trailing
        ) {
            if showsBracket {
                ReplyThreadBracket(opensToTrailing: bracketOnLeadingEdge)
                    .stroke(
                        Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 38)
                    .padding(.vertical, 28)
                    .allowsHitTesting(false)
            }
        }
    }

    private var replyCountRow: some View {
        HStack {
            if rootMessage.direction == .outgoing { Spacer(minLength: 40) }
            Text(replyCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.59, blue: 1))
                .padding(.horizontal, 13)
            if rootMessage.direction == .incoming { Spacer(minLength: 40) }
        }
    }

    private var replyCountText: String {
        let value = replies.count
        let mod10 = value % 10
        let mod100 = value % 100
        let noun: String
        if mod10 == 1, mod100 != 11 {
            noun = "ответ"
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            noun = "ответа"
        } else {
            noun = "ответов"
        }
        return "\(value) \(noun)"
    }
}

@MainActor
private struct ReplyThreadMessageRow: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let maximumBubbleWidth: CGFloat
    let isSelected: Bool
    let showsDeliveryStatus: Bool

    var body: some View {
        VStack(
            alignment: message.direction == .outgoing ? .trailing : .leading,
            spacing: 4
        ) {
            if message.isGroupMessage, message.direction == .incoming {
                Text(message.senderDisplayName ?? model.displayName(for: message.senderJID))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom) {
                if message.direction == .outgoing { Spacer(minLength: 44) }
                focusedBubble
                    .frame(maxWidth: maximumBubbleWidth, alignment: message.direction == .outgoing ? .trailing : .leading)
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.5) : Color.clear,
                        radius: isSelected ? 22 : 0,
                        y: isSelected ? 8 : 0
                    )
                    .scaleEffect(isSelected ? 1.018 : 1)
                if message.direction == .incoming { Spacer(minLength: 44) }
            }

            if showsDeliveryStatus, message.direction == .outgoing {
                Text(deliveryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.trailing, 13)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isSelected)
        .task(id: message.remoteAttachmentURL) {
            if isVisualMedia {
                await model.prepareMediaPreview(message)
            }
        }
    }

    @ViewBuilder
    private var focusedBubble: some View {
        if isVisualMedia {
            visualMediaBubble
        } else {
            HStack(spacing: 10) {
                if let icon = nonVisualMediaIcon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(displayText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, message.direction == .incoming ? 17 : 14)
            .padding(.trailing, message.direction == .outgoing ? 17 : 14)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(focusedBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var visualMediaBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.white.opacity(0.08)
                mediaThumbnail
                if message.kind != .photo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.42), in: Circle())
                }
            }
            .frame(width: min(maximumBubbleWidth, 430), height: 190)
            .clipped()

            Text(message.previewText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
        }
        .background(focusedBubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var mediaThumbnail: some View {
        if let data = model.mediaThumbnail(for: message) {
#if os(iOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                mediaPlaceholder
            }
#elseif os(macOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                mediaPlaceholder
            }
#endif
        } else {
            mediaPlaceholder
        }
    }

    private var mediaPlaceholder: some View {
        Image(systemName: message.kind == .photo ? "photo.fill" : "video.fill")
            .font(.system(size: 42, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var focusedBubbleBackground: some View {
        if message.direction == .outgoing {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.51, blue: 0.96),
                    Color(red: 0.10, green: 0.63, blue: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [Color.white.opacity(0.34), Color.white.opacity(0.23)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var isVisualMedia: Bool {
        !message.isRetracted
            && (message.kind == .photo || message.kind == .video || message.kind == .videoNote)
    }

    private var nonVisualMediaIcon: String? {
        switch message.kind {
        case .attachment: return "doc.fill"
        case .audio: return "music.note"
        case .voice: return "waveform"
        case .location: return "location.fill"
        case .text, .system, .photo, .video, .videoNote: return nil
        }
    }

    private var displayText: String {
        message.isRetracted ? "Сообщение удалено" : message.body
    }

    private var deliveryText: String {
        let state: String
        switch message.delivery {
        case .sending: state = "Отправка"
        case .sent: state = "Отправлено"
        case .delivered: state = "Доставлено"
        case .failed: state = "Не отправлено"
        case .read: state = "Прочитано"
        }
        let value = Calendar.current.isDateInToday(message.timestamp)
            ? message.timestamp.formatted(date: .omitted, time: .shortened)
            : message.timestamp.formatted(date: .numeric, time: .omitted)
        return "\(state) \(value)"
    }
}

#Preview {
    ReplyThreadOverlay(
        model: PreviewSupport.model,
        rootMessage: PreviewSupport.message(
            body: "Кто пойдёт на конференцию?",
            timestamp: Date().addingTimeInterval(-3_600)
        ),
        replies: [
            PreviewSupport.message(
                id: "preview-reply-1",
                body: "Я пойду!",
                timestamp: Date().addingTimeInterval(-2_400)
            ),
            PreviewSupport.message(
                id: "preview-reply-2",
                body: "Я тоже, но опоздаю на полчаса",
                timestamp: Date().addingTimeInterval(-1_800)
            ),
        ],
        selectedReplyID: "preview-reply-1",
        onDismiss: {}
    )
}

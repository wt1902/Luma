import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

@MainActor
struct MessageBubble: View {
    let model: AppModel
    let message: ChatMessage
    let isSelectionMode: Bool
    let isSelected: Bool
    let onAttachmentTap: () -> Void
    let onEdit: () -> Void
    let onReply: () -> Void
    let onForward: () -> Void
    let onRetry: () -> Void
    let onToggleSelection: () -> Void
    let onBeginSelection: () -> Void
    let onRetract: () -> Void
    let onDelete: () -> Void
    let onReplyTap: (String) -> Void
    let onReact: (String) -> Void
    let onReactPicker: () -> Void

    @State private var replySwipeOffset: CGFloat = 0
    @State private var replySwipeArmed = false
    @State private var replySwipeLocked = false
    @State private var scrollOwnsGesture = false

    var body: some View {
        ZStack {
            replySwipeIndicator
            messageContainer
                .offset(x: replySwipeOffset)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityIdentifier("bubble-\(message.clientID)")
        .onTapGesture {
            guard isSelectionMode else { return }
            onToggleSelection()
        }
        .padding(
            .vertical,
            message.kind == .photo || message.kind == .video ? 7 : 2
        )
        .onChange(of: isSelectionMode) { _, selecting in
            guard selecting else { return }
            replySwipeOffset = 0
            replySwipeArmed = false
            replySwipeLocked = false
            scrollOwnsGesture = false
        }
        .contextMenu {
            if !isSelectionMode {
                if message.canBeReactedTo {
                    Button(action: onReactPicker) {
                        Label("Реакция", systemImage: "face.smiling")
                    }
                }
                if message.canBeRepliedTo {
                    Button(action: onReply) {
                        Label("Ответить", systemImage: "arrowshape.turn.up.left")
                    }
                }
                if message.canBeForwarded {
                    Button(action: onForward) {
                        Label("Переслать", systemImage: "arrowshape.turn.up.right")
                    }
                }
                if message.hasText {
                    Button(action: copyText) {
                        Label("Копировать текст", systemImage: "doc.on.doc")
                    }
                }
                if message.kind.isMedia, !message.isRetracted {
                    Button {
                        Task { await MediaDownloadService.save(message, model: model) }
                    } label: {
                        Label("Сохранить", systemImage: "square.and.arrow.down")
                    }
                }
                if model.canRetryMediaMessage(message) {
                    Button(action: onRetry) {
                        Label("Повторить отправку", systemImage: "arrow.clockwise")
                    }
                }
                if message.canBeEdited {
                    Button(action: onEdit) {
                        Label("Редактировать", systemImage: "pencil")
                    }
                }
                Button(action: onBeginSelection) {
                    Label("Выбрать", systemImage: "checkmark.circle")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить у меня", systemImage: "trash")
                }
                if message.canBeRetracted {
                    Button(role: .destructive, action: onRetract) {
                        Label("Удалить у всех", systemImage: "trash.slash")
                    }
                }
            }
        }
        .accessibilityLabel(Text(selectionAccessibilityLabel))
        .accessibilityAction(named: Text(isSelected ? "Убрать из выбранных" : "Выбрать")) {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onBeginSelection()
            }
        }
    }

    private func copyText() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.body, forType: .string)
        #else
            UIPasteboard.general.string = message.body
        #endif
    }

    private var messageContainer: some View {
        HStack(spacing: 2) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 34)
                    .padding(.leading, 7)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                if hasReplyReference {
                    compactReplyReference
                }
                messageRow
            }
            .allowsHitTesting(!isSelectionMode)
        }
    }

    private var replySwipeIndicator: some View {
        HStack {
            if replySwipeOffset >= 0 {
                replySwipeIcon
                Spacer()
            } else {
                Spacer()
                replySwipeIcon
            }
        }
        .padding(.horizontal, 18)
        .allowsHitTesting(false)
        .opacity(replySwipeOffset == 0 ? 0 : 1)
    }

    private var replySwipeIcon: some View {
        Image(
            systemName: replySwipeArmed
                ? "arrowshape.turn.up.left.fill"
                : "arrowshape.turn.up.left"
        )
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .scaleEffect(x: replySwipeOffset > 0 ? -1 : 1, y: 1)
        .scaleEffect(
            CGFloat(0.8) + CGFloat(0.2) * MessageReplySwipePolicy.progress(for: replySwipeOffset)
        )
        .opacity(
            Double(
                CGFloat(0.35) + CGFloat(0.65)
                    * MessageReplySwipePolicy.progress(for: replySwipeOffset)
            ))
    }

    private var replySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Arbitration: once the touch is clearly vertical the scroll
                // view owns it for good, so a later horizontal arc can never
                // move bubbles mid-scroll. A reply swipe locks in only while
                // the finger is still moving mostly horizontally.
                if !replySwipeLocked, !scrollOwnsGesture {
                    if MessageReplySwipePolicy.canLock(value.translation) {
                        replySwipeLocked = true
                    } else if abs(value.translation.height) > 16,
                        abs(value.translation.width) < abs(value.translation.height)
                    {
                        scrollOwnsGesture = true
                    }
                }
                guard replySwipeLocked, !scrollOwnsGesture else { return }
                let offset = MessageReplySwipePolicy.offset(
                    locked: replySwipeLocked,
                    translation: value.translation
                )
                guard offset != 0 else {
                    // Vertical (or not clearly horizontal) movement: snap the
                    // indicator back and never publish per-cell state changes
                    // during an ordinary timeline scroll.
                    if replySwipeOffset != 0 || replySwipeArmed {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            replySwipeOffset = 0
                        }
                        replySwipeArmed = false
                    }
                    return
                }
                replySwipeOffset = offset
                let armed = MessageReplySwipePolicy.shouldReply(
                    locked: replySwipeLocked,
                    translation: value.translation,
                    predictedEndTranslation: value.translation
                )
                if armed, !replySwipeArmed {
                    replySwipeFeedback()
                }
                replySwipeArmed = armed
            }
            .onEnded { value in
                // The lock is a hint, not a requirement: a fast flick may
                // deliver no intermediate frame that passes canLock, yet its
                // end state is still a clear horizontal swipe. scrollOwnsGesture
                // alone protects the timeline from reply activation.
                let shouldReply =
                    !scrollOwnsGesture
                    && MessageReplySwipePolicy.shouldReply(
                        locked: replySwipeLocked,
                        translation: value.translation,
                        predictedEndTranslation: value.predictedEndTranslation
                    )
                replySwipeLocked = false
                scrollOwnsGesture = false
                if replySwipeOffset != 0 || replySwipeArmed {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        replySwipeOffset = 0
                        replySwipeArmed = false
                    }
                }
                if shouldReply {
                    onReply()
                }
            }
    }

    private func replySwipeFeedback() {
        #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private var selectionAccessibilityLabel: String {
        guard isSelectionMode else { return message.previewText }
        return "\(message.previewText), \(isSelected ? "выбрано" : "не выбрано")"
    }

    private var messageRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.direction == .outgoing { Spacer(minLength: sideSpacerMinimum) }

            VStack(alignment: message.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                if message.isGroupMessage, message.direction == .incoming {
                    Text(message.senderDisplayName ?? model.displayName(for: message.senderJID))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(senderColor)
                        .padding(.horizontal, 8)
                }
                // The drag lives on the bubble itself so a swipe can only start
                // a reply when it begins on the bubble — not on the empty
                // space beside it, the sender name, or the metadata row.
                messageContent
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        replySwipeGesture,
                        including: !isSelectionMode && message.canBeRepliedTo ? .gesture : .none
                    )

                if !reactionSummaries.isEmpty {
                    reactionStrip
                }

                if hasReplyReference {
                    replyWarningIndicators
                } else {
                    standardMetadata
                }
            }

            if message.direction == .incoming { Spacer(minLength: sideSpacerMinimum) }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let targetID = message.replyToID,
                message.kind == .text || message.kind == .system
            else { return }
            onReplyTap(targetID)
        }
    }

    private var sideSpacerMinimum: CGFloat {
        message.kind.isMedia ? 16 : 54
    }

    @ViewBuilder
    private var replyWarningIndicators: some View {
        if message.security != .omemo || message.delivery == .failed {
            HStack(spacing: 4) {
                if message.security != .omemo {
                    Image(
                        systemName: message.security == .plaintext
                            ? "lock.open" : "exclamationmark.shield"
                    )
                    .foregroundStyle(message.security == .plaintext ? .orange : .red)
                }
                if message.delivery == .failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
    }

    private var standardMetadata: some View {
        HStack(spacing: 4) {
            if message.callHistory == nil, message.security != .omemo {
                Image(
                    systemName: message.security == .plaintext
                        ? "lock.open" : "exclamationmark.shield"
                )
                .foregroundStyle(message.security == .plaintext ? .orange : .red)
            }
            if message.editedAt != nil {
                Text("изм.")
            }
            Text(message.timestamp, format: .dateTime.hour().minute())
            if message.direction == .outgoing, message.callHistory == nil {
                Image(systemName: deliveryIcon)
                    .foregroundStyle(message.delivery == .failed ? .red : .secondary)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.isRetracted {
            HStack(spacing: 7) {
                Image(systemName: "trash.slash")
                Text("Сообщение удалено")
                    .italic()
            }
            .font(.subheadline)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(
                message.direction == .outgoing ? Color.white.opacity(0.86) : Color.secondary
            )
            .background(bubbleBackground)
            .clipShape(messageBubbleShape)
        } else {
            regularMessageContent
        }
    }

    @ViewBuilder
    private var regularMessageContent: some View {
        switch message.kind {
        case .videoNote:
            VideoNotePreview(
                model: model,
                message: message,
                onFallbackTap: onAttachmentTap
            )
        case .video:
            VideoAttachmentPreview(
                model: model,
                message: message,
                onFallbackTap: onAttachmentTap
            )
        case .audio, .voice:
            AudioMessagePlayer(
                model: model,
                message: message,
                onFallbackTap: onAttachmentTap
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(bubbleBackground)
            .clipShape(messageBubbleShape)
        case .photo:
            PhotoAttachmentPreview(
                model: model,
                message: message,
                onFallbackTap: onAttachmentTap
            )
        case .location:
            if let location = GeoLocation(uri: message.body) {
                LocationMessagePreview(location: location)
            } else {
                Text(message.body)
                    .lumaTextSelection()
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(message.direction == .outgoing ? Color.white : Color.primary)
                    .background(bubbleBackground)
                    .clipShape(messageBubbleShape)
            }
        case .attachment:
            Button(action: onAttachmentTap) {
                mediaContent
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(message.direction == .outgoing ? Color.white : Color.primary)
            .background(bubbleBackground)
            .clipShape(messageBubbleShape)
        case .text, .system:
            if let callHistory = message.callHistory {
                callHistoryContent(callHistory)
            } else {
                Text(message.body)
                    .lumaTextSelection()
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(message.direction == .outgoing ? Color.white : Color.primary)
                    .background(bubbleBackground)
                    .clipShape(messageBubbleShape)
            }
        }
    }

    private func callHistoryContent(_ history: CallHistoryMetadata) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        callAccentColor(for: history).opacity(
                            message.direction == .outgoing ? 0.28 : 0.14
                        ))
                Image(systemName: history.isVideo ? "video.fill" : "phone.fill")
                    .font(.system(size: 17, weight: .semibold))
                Image(
                    systemName: message.direction == .outgoing
                        ? "arrow.up.right" : "arrow.down.left"
                )
                .font(.system(size: 8, weight: .heavy))
                .padding(3)
                .background(Circle().fill(callDirectionBadgeBackground))
                .offset(x: 14, y: 14)
            }
            .frame(width: 42, height: 42)
            .foregroundStyle(callIconForeground(for: history))

            VStack(alignment: .leading, spacing: 3) {
                Text(message.callTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let subtitle = message.callSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.78)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .foregroundStyle(message.direction == .outgoing ? Color.white : Color.primary)
        .background(bubbleBackground)
        .clipShape(messageBubbleShape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message.callTitle))
    }

    private func callAccentColor(for history: CallHistoryMetadata) -> Color {
        switch history.outcome {
        case .completed:
            return .green
        case .declined, .missed, .unanswered, .failed:
            return .red
        case .cancelled, .answeredElsewhere:
            return .secondary
        }
    }

    private func callIconForeground(for history: CallHistoryMetadata) -> Color {
        message.direction == .outgoing ? .white : callAccentColor(for: history)
    }

    private var callDirectionBadgeBackground: Color {
        message.direction == .outgoing
            ? Color(red: 0.13, green: 0.57, blue: 0.94)
            : Color.secondary.opacity(0.16)
    }

    private var reactionSummaries: [MessageReactionSummary] {
        message.reactionSummaries(ownJID: model.account?.normalizedJID)
    }

    private var reactionStrip: some View {
        HStack(spacing: 5) {
            ForEach(reactionSummaries) { summary in
                Button {
                    onReact(summary.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(summary.emoji)
                        Text(String(summary.count))
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        summary.includesOwnReaction
                            ? Color.accentColor.opacity(0.2)
                            : Color.secondary.opacity(0.12),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().stroke(
                            summary.includesOwnReaction
                                ? Color.accentColor.opacity(0.55)
                                : Color.secondary.opacity(0.16),
                            lineWidth: 0.8
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(summary.emoji), реакций: \(summary.count)")
            }
        }
        .padding(.horizontal, 4)
    }

    private var hasReplyReference: Bool {
        message.replyToID != nil || message.replyPreview != nil
    }

    private var compactReplyReference: some View {
        Group {
            if let targetID = message.replyToID {
                Button {
                    onReplyTap(targetID)
                } label: {
                    compactReplyLayout
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть ветку ответа")
            } else {
                compactReplyLayout
            }
        }
        .opacity(0.56)
        .padding(.bottom, -2)
        .task(id: replyTarget?.remoteAttachmentURL) {
            if let replyTarget,
                replyTarget.kind == .photo
                    || replyTarget.kind == .video
                    || replyTarget.kind == .videoNote
            {
                await model.prepareMediaPreview(replyTarget)
            }
        }
    }

    private var compactReplyLayout: some View {
        HStack {
            if compactTargetDirection == .outgoing {
                Spacer(minLength: 58)
            }

            VStack(
                alignment: compactTargetDirection == .outgoing ? .trailing : .leading,
                spacing: -1
            ) {
                compactSourceBubble
                ReplyThreadCurve(sourceDirection: compactTargetDirection)
                    .stroke(
                        compactReplyColor.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .frame(width: 58, height: 34)
                    .offset(x: compactTargetDirection == .outgoing ? -18 : 18)
            }

            if compactTargetDirection == .incoming {
                Spacer(minLength: 58)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }

    private var compactSourceBubble: some View {
        HStack(spacing: 7) {
            compactReplyThumbnail
            Text(replyText)
                .font(.callout.weight(.medium))
                .foregroundStyle(compactReplyColor)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, compactTargetDirection == .incoming ? 12 : 10)
        .padding(.trailing, compactTargetDirection == .outgoing ? 12 : 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 230, minHeight: 34, alignment: .leading)
        .background(Color.primary.opacity(0.018))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(compactReplyColor.opacity(0.75), lineWidth: 1.25)
        }
    }

    @ViewBuilder
    private var compactReplyThumbnail: some View {
        if let target = replyTarget, target.kind != .text, target.kind != .system {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                replyThumbnailImage(for: target)
            }
            .frame(width: 27, height: 27)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private func replyThumbnailImage(for target: ChatMessage) -> some View {
        if let data = model.mediaThumbnail(for: target) {
            #if os(iOS)
                if let image = ChatMediaImageCache.image(for: target, data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: replyMediaIcon(for: target.kind))
                        .foregroundStyle(compactReplyColor)
                }
            #elseif os(macOS)
                if let image = ChatMediaImageCache.image(for: target, data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: replyMediaIcon(for: target.kind))
                        .foregroundStyle(compactReplyColor)
                }
            #endif
        } else {
            Image(systemName: replyMediaIcon(for: target.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(compactReplyColor)
        }
    }

    private var replyTarget: ChatMessage? {
        message.replyToID.flatMap { model.message(withID: $0, in: message.conversationID) }
    }

    private var compactTargetDirection: ChatMessage.Direction {
        if let direction = replyTarget?.direction { return direction }
        return message.direction == .outgoing ? .incoming : .outgoing
    }

    private var compactReplyColor: Color {
        compactTargetDirection == .outgoing
            ? Color(red: 0.18, green: 0.59, blue: 0.98)
            : Color.secondary
    }

    private var replyText: String {
        replyTarget?.quotePreview ?? message.replyPreview ?? "Исходное сообщение недоступно"
    }

    private var mediaContent: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(.white.opacity(message.direction == .outgoing ? 0.22 : 0.12))
                    .frame(
                        width: message.kind == .videoNote ? 58 : 38,
                        height: message.kind == .videoNote ? 58 : 38)
                Image(systemName: mediaIcon)
                    .font(.system(size: message.kind == .videoNote ? 24 : 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(mediaTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(mediaSubtitle)
                    .font(.caption)
                    .opacity(0.8)
            }
        }
    }

    private var mediaTitle: String {
        switch message.kind {
        case .photo: return "Фото"
        case .video: return "Видео"
        case .audio: return message.localFilename ?? "Аудио"
        case .voice: return "Голосовое сообщение"
        case .videoNote: return "Видеосообщение"
        case .attachment: return message.localFilename ?? message.body
        case .location: return "Геопозиция"
        case .text, .system: return message.body
        }
    }

    private var mediaSubtitle: String {
        if message.remoteAttachmentURL == nil {
            return "Подготовка…"
        }
        var parts: [String] = []
        if let duration = message.duration {
            let seconds = max(0, Int(duration.rounded()))
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        if let byteCount = message.byteCount {
            parts.append(
                ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        return parts.isEmpty ? "Нажмите для просмотра" : parts.joined(separator: " · ")
    }

    private var mediaIcon: String {
        switch message.kind {
        case .attachment: return "doc.fill"
        case .photo: return "photo.fill"
        case .video: return "play.rectangle.fill"
        case .audio: return "music.note"
        case .voice: return "waveform"
        case .videoNote: return "video.circle.fill"
        case .location: return "location.fill"
        case .text, .system: return "doc.fill"
        }
    }

    private func replyMediaIcon(for kind: ChatMessage.Kind) -> String {
        switch kind {
        case .photo: return "photo.fill"
        case .video: return "play.fill"
        case .audio: return "music.note"
        case .voice: return "waveform"
        case .videoNote: return "video.circle.fill"
        case .attachment: return "doc.fill"
        case .location: return "location.fill"
        case .text, .system: return "quote.bubble.fill"
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.direction == .outgoing {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.51, blue: 0.94),
                    Color(red: 0.12, green: 0.63, blue: 0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.secondary.opacity(0.13)
        }
    }

    private var messageBubbleShape: ChatBubbleShape {
        ChatBubbleShape(isOutgoing: message.direction == .outgoing)
    }

    private var deliveryIcon: String {
        switch message.delivery {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var senderColor: Color {
        color(for: message.senderJID)
    }

    private func color(for jid: String) -> Color {
        let seed = jid.utf8.reduce(UInt64(2_166_136_261)) { value, byte in
            (value ^ UInt64(byte)) &* 16_777_619
        }
        return Color(
            hue: Double(seed % 360) / 360,
            saturation: 0.72,
            brightness: 0.78
        )
    }
}

extension View {
    @ViewBuilder
    fileprivate func lumaTextSelection() -> some View {
        #if os(macOS)
            textSelection(.enabled)
        #else
            self
        #endif
    }
}

#Preview("Входящее") {
    MessageBubble(
        model: PreviewSupport.model,
        message: PreviewSupport.message(),
        isSelectionMode: false,
        isSelected: false,
        onAttachmentTap: {},
        onEdit: {},
        onReply: {},
        onForward: {},
        onRetry: {},
        onToggleSelection: {},
        onBeginSelection: {},
        onRetract: {},
        onDelete: {},
        onReplyTap: { _ in },
        onReact: { _ in },
        onReactPicker: {}
    )
    .padding()
}

#Preview("Исходящее") {
    MessageBubble(
        model: PreviewSupport.model,
        message: PreviewSupport.message(
            senderJID: "me@example.org",
            body: "Отлично! Созвонимся вечером?",
            direction: .outgoing,
            delivery: .delivered
        ),
        isSelectionMode: false,
        isSelected: false,
        onAttachmentTap: {},
        onEdit: {},
        onReply: {},
        onForward: {},
        onRetry: {},
        onToggleSelection: {},
        onBeginSelection: {},
        onRetract: {},
        onDelete: {},
        onReplyTap: { _ in },
        onReact: { _ in },
        onReactPicker: {}
    )
    .padding()
}

#Preview("Фото") {
    MessageBubble(
        model: PreviewSupport.model,
        message: PreviewSupport.photoMessage(),
        isSelectionMode: false,
        isSelected: false,
        onAttachmentTap: {},
        onEdit: {},
        onReply: {},
        onForward: {},
        onRetry: {},
        onToggleSelection: {},
        onBeginSelection: {},
        onRetract: {},
        onDelete: {},
        onReplyTap: { _ in },
        onReact: { _ in },
        onReactPicker: {}
    )
    .padding()
}

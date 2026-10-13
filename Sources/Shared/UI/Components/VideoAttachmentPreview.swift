import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct VideoAttachmentPreview: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let onFallbackTap: () -> Void

    private let islandWidth: CGFloat = 268

    var body: some View {
        Button(action: openViewer) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.17, blue: 0.29),
                        Color(red: 0.09, green: 0.43, blue: 0.64)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                thumbnail
                    .padding(6)

                if model.isMediaPreviewLoading(message) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(15)
                        .background(.black.opacity(0.38), in: Circle())
                }

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if let filename = message.localFilename {
                            Text(filename)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(metadataText)
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.48), in: Capsule())
                }
                .padding(9)
            }
            .frame(width: islandWidth, height: islandHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .task(id: message.remoteAttachmentURL) {
            await model.prepareMediaPreview(message)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Видео, \(metadataText)")
        .accessibilityHint("Открывает видео на весь экран")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = model.mediaThumbnail(for: message) {
#if os(iOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
#elseif os(macOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
#endif
        } else {
            Image(systemName: "film.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var metadataText: String {
        var parts: [String] = []
        if let duration = message.duration {
            parts.append(MediaTimeFormatter.string(duration))
        }
        if let byteCount = message.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        return parts.isEmpty ? "Видео" : parts.joined(separator: " · ")
    }

    private var islandHeight: CGFloat {
        let contentWidth = islandWidth - 12
        let naturalHeight = contentWidth / thumbnailAspectRatio + 12
        return min(max(naturalHeight, 164), 250)
    }

    private var thumbnailAspectRatio: CGFloat {
        guard let data = model.mediaThumbnail(for: message) else { return 16 / 9 }
#if os(iOS)
        guard let image = ChatMediaImageCache.image(for: message, data: data),
              image.size.height > 0 else { return 16 / 9 }
        return max(0.7, min(2.2, image.size.width / image.size.height))
#elseif os(macOS)
        guard let image = ChatMediaImageCache.image(for: message, data: data),
              image.size.height > 0 else { return 16 / 9 }
        return max(0.7, min(2.2, image.size.width / image.size.height))
#endif
    }

    private func openViewer() {
        Task {
            await model.presentMediaViewer(message)
            if model.mediaViewerItem?.id != message.clientID,
               message.remoteAttachmentURL == nil {
                onFallbackTap()
            }
        }
    }
}

#Preview {
    VideoAttachmentPreview(
        model: PreviewSupport.model,
        message: PreviewSupport.videoMessage(),
        onFallbackTap: {}
    )
    .padding()
}

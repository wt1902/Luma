import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct PhotoAttachmentPreview: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let onFallbackTap: () -> Void

    private let islandWidth: CGFloat = 268

    var body: some View {
        Button(action: openViewer) {
            ZStack {
                Color.secondary.opacity(0.12)
                thumbnail
                    .padding(6)

                if model.isMediaPreviewLoading(message) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                        .padding(15)
                        .background(.black.opacity(0.34), in: Circle())
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
                        Text(sizeText)
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
        .accessibilityLabel("Фото, \(sizeText)")
        .accessibilityHint("Открывает фото на весь экран")
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
            Image(systemName: "photo.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var sizeText: String {
        guard let byteCount = message.byteCount else { return "Фото" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private var islandHeight: CGFloat {
        let contentWidth = islandWidth - 12
        let naturalHeight = contentWidth / thumbnailAspectRatio + 12
        return min(max(naturalHeight, 164), 328)
    }

    private var thumbnailAspectRatio: CGFloat {
        guard let data = model.mediaThumbnail(for: message) else { return 4 / 3 }
#if os(iOS)
        guard let image = ChatMediaImageCache.image(for: message, data: data),
              image.size.height > 0 else { return 4 / 3 }
        return max(0.45, min(2.2, image.size.width / image.size.height))
#elseif os(macOS)
        guard let image = ChatMediaImageCache.image(for: message, data: data),
              image.size.height > 0 else { return 4 / 3 }
        return max(0.45, min(2.2, image.size.width / image.size.height))
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
    PhotoAttachmentPreview(
        model: PreviewSupport.model,
        message: PreviewSupport.photoMessage(),
        onFallbackTap: {}
    )
    .padding()
}

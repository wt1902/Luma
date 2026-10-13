import AVFoundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct VideoNotePreview: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let onFallbackTap: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    private var diameter: CGFloat { isPlaying ? 176 : 144 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.30, blue: 0.56),
                    Color(red: 0.07, green: 0.64, blue: 0.83)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            thumbnail

            if let player {
                InlineVideoPlayer(player: player)
            }

            if previewURL == nil, model.isMediaPreviewLoading(message) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            } else if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(17)
                    .background(.black.opacity(0.34), in: Circle())
            }

            VStack {
                Spacer()
                HStack {
//                    Spacer()
                    Text(durationText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.48), in: Capsule())
                }
                .padding(12)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isPlaying)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        .contentShape(Circle())
        .onTapGesture(perform: togglePlayback)
        .task(id: message.remoteAttachmentURL) {
            await model.prepareMediaPreview(message)
            configurePlayerIfNeeded()
        }
        .onChange(of: previewURL) { _, _ in
            configurePlayerIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player?.currentItem else { return }
            player?.seek(to: .zero)
            isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaExclusiveMediaPlayback)) { notification in
            guard let activeID = notification.object as? String,
                  activeID != message.clientID else { return }
            player?.pause()
            isPlaying = false
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
        .accessibilityLabel("Видеосообщение, \(durationText)")
        .accessibilityHint("Нажмите для воспроизведения или паузы")
    }

    private var previewURL: URL? {
        model.mediaPreviewURL(for: message)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = model.mediaThumbnail(for: message) {
#if os(iOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
#elseif os(macOS)
            if let image = ChatMediaImageCache.image(for: message, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
#endif
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var durationText: String {
        let seconds = max(0, Int((message.duration ?? 0).rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func configurePlayerIfNeeded() {
        guard player == nil, let previewURL else { return }
        let player = AVPlayer(url: previewURL)
        player.actionAtItemEnd = .pause
        self.player = player
    }

    private func togglePlayback() {
        guard previewURL != nil else {
            onFallbackTap()
            return
        }
        configurePlayerIfNeeded()
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            model.audioPlayback.stop()
            NotificationCenter.default.post(
                name: .lumaExclusiveMediaPlayback,
                object: message.clientID
            )
            player.play()
        }
        isPlaying.toggle()
    }
}

#Preview {
    VideoNotePreview(
        model: PreviewSupport.model,
        message: PreviewSupport.videoNoteMessage(),
        onFallbackTap: {}
    )
    .padding()
}

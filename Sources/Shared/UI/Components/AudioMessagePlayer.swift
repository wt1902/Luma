import Foundation
import SwiftUI

@MainActor
struct AudioMessagePlayer: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: MediaPlaybackCoordinator
    let message: ChatMessage
    let onFallbackTap: () -> Void

    init(
        model: AppModel,
        message: ChatMessage,
        onFallbackTap: @escaping () -> Void
    ) {
        self.model = model
        _playback = ObservedObject(wrappedValue: model.audioPlayback)
        self.message = message
        self.onFallbackTap = onFallbackTap
    }

    var body: some View {
        Group {
            if message.kind == .voice {
                voicePlayer
            } else {
                musicPlayer
            }
        }
        .frame(width: 252, alignment: .leading)
        .task(id: message.remoteAttachmentURL) {
            await model.prepareMediaPreview(message)
        }
        .accessibilityElement(children: .contain)
    }

    private var voicePlayer: some View {
        HStack(spacing: 10) {
            playButton

            VStack(alignment: .leading, spacing: 3) {
                WaveformScrubber(
                    samples: model.audioWaveform(for: message),
                    progress: progress,
                    activeColor: accent,
                    inactiveColor: secondaryAccent,
                    onSeek: seek
                )
                .frame(height: 30)

                HStack(spacing: 7) {
                    Text(voiceTimeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryText)
                    Spacer()
                    Button(action: saveToFiles) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сохранить в Файлы")
                    Button(action: playback.cycleVoiceRate) {
                        Text(rateText)
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скорость воспроизведения \(rateText)")
                }
            }
        }
    }

    private var musicPlayer: some View {
        HStack(spacing: 11) {
            playButton

            VStack(alignment: .leading, spacing: 4) {
                Text(message.localFilename ?? "Аудиофайл")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)

                MediaProgressScrubber(
                    progress: progress,
                    activeColor: accent,
                    inactiveColor: secondaryAccent,
                    onSeek: seek
                )
                .frame(height: 12)

                HStack(spacing: 6) {
                    Text(audioTimeText)
                    if let byteCount = message.byteCount {
                        Text("·")
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(byteCount),
                            countStyle: .file
                        ))
                    }
                    Spacer()
                    Button(action: saveToFiles) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сохранить в Файлы")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(secondaryText)
            }
        }
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            ZStack {
                Circle()
                    .fill(accent.opacity(message.direction == .outgoing ? 0.2 : 0.14))
                if model.isMediaPreviewLoading(message) && localURL == nil {
                    ProgressView()
                        .tint(accent)
                        .controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Пауза" : "Воспроизвести")
    }

    private var localURL: URL? {
        model.mediaPreviewURL(for: message)
    }

    private var isCurrent: Bool {
        playback.currentMessageID == message.clientID
    }

    private var isPlaying: Bool {
        isCurrent && playback.isPlaying
    }

    private var totalDuration: TimeInterval {
        let value = isCurrent && playback.duration > 0
            ? playback.duration
            : (message.duration ?? 0)
        return max(0, value)
    }

    private var displayedTime: TimeInterval {
        isCurrent ? playback.currentTime : 0
    }

    private var progress: Double {
        guard isCurrent, totalDuration > 0 else { return 0 }
        return max(0, min(1, playback.currentTime / totalDuration))
    }

    private var voiceTimeText: String {
        if isCurrent, playback.currentTime > 0 {
            return "\(MediaTimeFormatter.string(displayedTime)) / \(MediaTimeFormatter.string(totalDuration))"
        }
        return MediaTimeFormatter.string(totalDuration)
    }

    private var audioTimeText: String {
        "\(MediaTimeFormatter.string(displayedTime)) / \(MediaTimeFormatter.string(totalDuration))"
    }

    private var rateText: String {
        if playback.voiceRate < 1.25 { return "1×" }
        if playback.voiceRate < 1.75 { return "1.5×" }
        return "2×"
    }

    private var accent: Color {
        message.direction == .outgoing ? .white : .accentColor
    }

    private var secondaryAccent: Color {
        message.direction == .outgoing ? .white.opacity(0.30) : Color.secondary.opacity(0.24)
    }

    private var primaryText: Color {
        message.direction == .outgoing ? .white : .primary
    }

    private var secondaryText: Color {
        message.direction == .outgoing ? .white.opacity(0.78) : .secondary
    }

    private func saveToFiles() {
        Task { await MediaDownloadService.save(message, model: model) }
    }

    private func togglePlayback() {
        guard let localURL else {
            Task {
                await model.prepareMediaPreview(message)
                guard let downloadedURL = model.mediaPreviewURL(for: message) else {
                    onFallbackTap()
                    return
                }
                playback.toggle(
                    messageID: message.clientID,
                    url: downloadedURL,
                    durationHint: message.duration,
                    isVoice: message.kind == .voice
                )
            }
            return
        }
        playback.toggle(
            messageID: message.clientID,
            url: localURL,
            durationHint: message.duration,
            isVoice: message.kind == .voice
        )
    }

    private func seek(_ fraction: Double) {
        guard let localURL else { return }
        playback.seek(
            messageID: message.clientID,
            url: localURL,
            durationHint: message.duration,
            isVoice: message.kind == .voice,
            fraction: fraction
        )
    }
}

private struct WaveformScrubber: View {
    let samples: [Float]
    let progress: Double
    let activeColor: Color
    let inactiveColor: Color
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    Capsule()
                        .fill(sampleProgress(index) <= progress ? activeColor : inactiveColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, geometry.size.height * CGFloat(sample)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(fraction(at: value.location.x, width: geometry.size.width))
                    }
            )
        }
        .accessibilityLabel("Позиция голосового сообщения")
        .accessibilityValue("\(Int(progress * 100)) процентов")
    }

    private func sampleProgress(_ index: Int) -> Double {
        guard samples.count > 1 else { return 0 }
        return Double(index) / Double(samples.count - 1)
    }
}

private struct MediaProgressScrubber: View {
    let progress: Double
    let activeColor: Color
    let inactiveColor: Color
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(inactiveColor).frame(height: 3)
                Capsule()
                    .fill(activeColor)
                    .frame(width: geometry.size.width * CGFloat(progress), height: 3)
                Circle()
                    .fill(activeColor)
                    .frame(width: 9, height: 9)
                    .offset(x: max(0, geometry.size.width * CGFloat(progress) - 4.5))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(fraction(at: value.location.x, width: geometry.size.width))
                    }
            )
        }
        .accessibilityLabel("Позиция аудиофайла")
        .accessibilityValue("\(Int(progress * 100)) процентов")
    }
}

private func fraction(at x: CGFloat, width: CGFloat) -> Double {
    guard width > 0 else { return 0 }
    return max(0, min(1, Double(x / width)))
}

enum MediaTimeFormatter {
    static func string(_ duration: TimeInterval) -> String {
        guard duration.isFinite else { return "0:00" }
        let seconds = max(0, Int(duration.rounded(.down)))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview("Голосовое") {
    AudioMessagePlayer(
        model: PreviewSupport.model,
        message: PreviewSupport.voiceMessage(),
        onFallbackTap: {}
    )
    .padding()
}

#Preview("Аудиофайл") {
    AudioMessagePlayer(
        model: PreviewSupport.model,
        message: PreviewSupport.message(
            body: "",
            kind: .audio,
            localFilename: "track.mp3",
            mimeType: "audio/mpeg",
            duration: 214,
            byteCount: 8_550_000
        ),
        onFallbackTap: {}
    )
    .padding()
}

import AVFoundation
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

actor MediaPreviewProcessor {
    struct Analysis: Sendable {
        let duration: TimeInterval?
        let thumbnailData: Data?
        let waveform: [Float]?
    }

    static let placeholderWaveform: [Float] = [
        0.24, 0.42, 0.30, 0.58, 0.76, 0.48, 0.34, 0.67,
        0.88, 0.61, 0.40, 0.73, 0.52, 0.31, 0.64, 0.82,
        0.45, 0.69, 0.91, 0.56, 0.38, 0.71, 0.49, 0.79,
        0.57, 0.35, 0.62, 0.86, 0.53, 0.72, 0.43, 0.65,
        0.84, 0.51, 0.32, 0.59, 0.75, 0.46, 0.68, 0.39,
        0.80, 0.55, 0.36, 0.70, 0.47, 0.63, 0.78, 0.44
    ]

    func analyze(
        url: URL,
        kind: ChatMessage.Kind,
        mimeType: String? = nil
    ) async -> Analysis {
        let asset = Self.mediaAsset(url: url, mimeType: mimeType)
        let duration: TimeInterval?
        if [.video, .audio, .voice, .videoNote].contains(kind) {
            duration = await mediaDuration(for: asset)
        } else {
            duration = nil
        }
        let thumbnailData: Data?
        if kind == .photo {
            thumbnailData = imageThumbnailData(for: url)
        } else if kind == .video || kind == .videoNote {
            thumbnailData = await videoThumbnailData(
                for: asset,
                duration: duration
            )
        } else {
            thumbnailData = nil
        }

        let waveform = kind == .voice ? voiceWaveform(for: url) : nil
        if kind == .video {
            let logger = Logger(subsystem: "Luma", category: "video-preview")
            logger.info(
                "analyze video: \(url.lastPathComponent) duration=\(String(describing: duration)) thumbnailBytes=\(thumbnailData?.count ?? 0)"
            )
        }
        return Analysis(
            duration: duration,
            thumbnailData: thumbnailData,
            waveform: waveform
        )
    }

    private func mediaDuration(for asset: AVURLAsset) async -> TimeInterval? {
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func videoThumbnailData(
        for asset: AVURLAsset,
        duration: TimeInterval?
    ) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 0.35,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 0.35,
            preferredTimescale: 600
        )

        let safeDuration = duration.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let preferredSecond = safeDuration.map {
            min(1, max(0.01, $0 * 0.25))
        } ?? 0.5
        let earlySecond = safeDuration.map {
            min(0.05, max(0, $0 * 0.1))
        } ?? 0.05
        var attemptedMilliseconds: Set<Int> = []
        for second in [preferredSecond, earlySecond, 0] {
            let key = Int((second * 1_000).rounded())
            guard attemptedMilliseconds.insert(key).inserted else { continue }
            do {
                let result = try await generator.image(
                    at: CMTime(seconds: second, preferredTimescale: 600)
                )
                if let data = jpegData(from: result.image) {
                    return data
                }
            } catch {
                Logger(subsystem: "Luma", category: "video-preview")
                    .error("image generator failed at \(second)s: \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    private func imageThumbnailData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return jpegData(from: image)
    }

    private func jpegData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func mediaAsset(url: URL, mimeType: String?) -> AVURLAsset {
        guard let mimeType, !mimeType.isEmpty else {
            return AVURLAsset(url: url)
        }
        // Supplying the MIME type is important for picker files whose temporary
        // extension does not describe the real QuickTime/HEVC container.
        return AVURLAsset(
            url: url,
            options: ["AVURLAssetOutOfBandMIMETypeKey": mimeType]
        )
    }

    private func voiceWaveform(for url: URL, sampleCount: Int = 48) -> [Float]? {
        do {
            let file = try AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let totalFrames = max(1, file.length)
            let capacity: AVAudioFrameCount = 4_096
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
            ) else { return nil }

            var peaks = Array(repeating: Float.zero, count: sampleCount)
            var processedFrames: AVAudioFramePosition = 0

            while processedFrames < totalFrames {
                let remaining = totalFrames - processedFrames
                let requested = AVAudioFrameCount(min(AVAudioFramePosition(capacity), remaining))
                try file.read(into: buffer, frameCount: requested)
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0, let channels = buffer.floatChannelData else { break }
                let channelCount = Int(buffer.format.channelCount)

                for frame in 0..<frameLength {
                    let absoluteFrame = processedFrames + AVAudioFramePosition(frame)
                    let bin = min(
                        sampleCount - 1,
                        Int(absoluteFrame * AVAudioFramePosition(sampleCount) / totalFrames)
                    )
                    var peak = Float.zero
                    for channel in 0..<channelCount {
                        peak = max(peak, abs(channels[channel][frame]))
                    }
                    peaks[bin] = max(peaks[bin], peak)
                }
                processedFrames += AVAudioFramePosition(frameLength)
            }

            guard let maximum = peaks.max(), maximum > 0 else {
                return Self.placeholderWaveform
            }
            return peaks.map { peak in
                max(0.08, min(1, sqrt(peak / maximum)))
            }
        } catch {
            return Self.placeholderWaveform
        }
    }
}

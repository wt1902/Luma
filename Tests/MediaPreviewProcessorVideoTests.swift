import AVFoundation
import XCTest
@testable import Luma

final class MediaPreviewProcessorVideoTests: XCTestCase {
    /// Reproduces the camera-video analysis on the simulator: the pipeline
    /// must produce a duration and a JPEG thumbnail for a freshly written
    /// HEVC QuickTime movie.
    func testVideoAnalysisProducesDurationAndThumbnail() async throws {
        let url = try await Self.makeTestMovie()
        defer { try? FileManager.default.removeItem(at: url) }

        let processor = MediaPreviewProcessor()
        let analysis = await processor.analyze(
            url: url,
            kind: .video,
            mimeType: "video/quicktime"
        )
        XCTAssertNotNil(analysis.duration)
        if let duration = analysis.duration {
            XCTAssertGreaterThan(duration, 0)
        }
        XCTAssertNotNil(analysis.thumbnailData)
        XCTAssertFalse(analysis.thumbnailData?.isEmpty ?? true)
    }

    private static func makeTestMovie() async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-camera-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: 640,
                AVVideoHeightKey: 480,
            ]
        )
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 480,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "test", code: 1)
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, nil, &buffer
            )
            adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return output
    }
}


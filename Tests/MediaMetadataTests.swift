import Foundation
import XCTest
@testable import Luma

final class MediaMetadataTests: XCTestCase {
    func testVoiceFilenameRoundTrip() throws {
        let filename = MediaMetadata.transportFilename(
            originalFilename: "voice-123.m4a",
            kind: .voice,
            duration: 12.345
        )

        let inferred = MediaMetadata.infer(from: filename)

        XCTAssertEqual(filename, "luma-voice-12345-voice-123.m4a")
        XCTAssertEqual(inferred.kind, .voice)
        XCTAssertEqual(try XCTUnwrap(inferred.duration), 12.345, accuracy: 0.001)
        XCTAssertNotNil(inferred.mimeType)
    }

    func testVideoNoteFilenameRoundTrip() throws {
        let filename = MediaMetadata.transportFilename(
            originalFilename: "video-note.mov",
            kind: .videoNote,
            duration: 59.9
        )

        let inferred = MediaMetadata.infer(from: filename)

        XCTAssertEqual(inferred.kind, .videoNote)
        XCTAssertEqual(try XCTUnwrap(inferred.duration), 59.9, accuracy: 0.001)
    }

    func testStandardExtensionsAreClassified() {
        XCTAssertEqual(MediaMetadata.infer(from: "image.jpg").kind, .photo)
        XCTAssertEqual(MediaMetadata.infer(from: "clip.mov").kind, .video)
        XCTAssertEqual(MediaMetadata.infer(from: "track.m4a").kind, .audio)
        XCTAssertEqual(MediaMetadata.infer(from: "archive.zip").kind, .attachment)
    }

    func testEncryptedTransportNameKeepsOriginalExtension() {
        let photo = MediaMetadata.transportFilename(
            originalFilename: "holiday.jpg",
            kind: .photo,
            duration: nil
        )
        let voice = MediaMetadata.transportFilename(
            originalFilename: "voice.m4a",
            kind: .voice,
            duration: 2.5
        )

        XCTAssertEqual(URL(fileURLWithPath: photo).pathExtension, "jpg")
        XCTAssertEqual(URL(fileURLWithPath: voice).pathExtension, "m4a")
        XCTAssertFalse(photo.hasSuffix(".aesgcm"))
        XCTAssertFalse(voice.hasSuffix(".aesgcm"))
    }
}

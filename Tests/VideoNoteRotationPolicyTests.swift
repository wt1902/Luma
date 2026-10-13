import XCTest
@testable import Luma

final class VideoNoteRotationPolicyTests: XCTestCase {
    func testPortraitNeedsClockwiseQuarterTurn() {
        // The sensor is landscape-native; an upright portrait circle must be
        // rotated 90 degrees clockwise in the QuickTime track matrix.
        XCTAssertEqual(
            VideoNoteRotationPolicy.angle(for: .portrait),
            90
        )
    }

    func testPortraitUpsideDownNeedsThreeQuarterTurn() {
        XCTAssertEqual(
            VideoNoteRotationPolicy.angle(for: .portraitUpsideDown),
            270
        )
    }

    func testLandscapeOrientationsMapToNativeAngles() {
        XCTAssertEqual(
            VideoNoteRotationPolicy.angle(for: .landscapeLeft),
            180
        )
        XCTAssertEqual(
            VideoNoteRotationPolicy.angle(for: .landscapeRight),
            0
        )
    }

    func testAllAnglesAreSupportedCaptureAngles() {
        let orientations: [VideoNoteRotationPolicy.InterfaceOrientation] = [
            .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight,
        ]
        for orientation in orientations {
            let angle = VideoNoteRotationPolicy.angle(for: orientation)
            XCTAssertTrue(
                [CGFloat(0), 90, 180, 270].contains(angle),
                "unexpected angle \(angle) for \(orientation)"
            )
        }
    }
}

import CoreGraphics
import XCTest
@testable import Luma

final class MessageReplySwipeTests: XCTestCase {
    func testRightToLeftSwipeReplies() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -70, height: 8),
            predictedEndTranslation: CGSize(width: -72, height: 9)
        ))
        XCTAssertLessThan(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: -70, height: 8)),
            0
        )
    }

    func testLeftToRightSwipeReplies() {
        XCTAssertTrue(MessageReplySwipePolicy.canLock(CGSize(width: 24, height: 10)))
        XCTAssertGreaterThan(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: 70, height: 8)),
            0
        )
        XCTAssertGreaterThan(
            MessageReplySwipePolicy.offset(locked: true, translation: CGSize(width: 70, height: 8)),
            0
        )
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: 70, height: 8),
            predictedEndTranslation: CGSize(width: 72, height: 9)
        ))
    }

    func testVerticalTimelineScrollDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -42, height: 80),
            predictedEndTranslation: CGSize(width: -50, height: 105)
        ))
    }

    func testDiagonalTimelineScrollDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -54, height: 44),
            predictedEndTranslation: CGSize(width: -76, height: 58)
        ))
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: -54, height: 44)),
            0
        )
    }

    func testDiagonalScrollAtOldThresholdDoesNotReply() {
        // width/height ≈ 1.5 passed the old 1.4 dominance and moved bubbles
        // during scrolling; the stricter policy must stay silent.
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -60, height: 40),
            predictedEndTranslation: CGSize(width: -60, height: 40)
        ))
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: -60, height: 40)),
            0
        )
    }

    func testShortSwipeDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -36, height: 4),
            predictedEndTranslation: CGSize(width: -48, height: 5)
        ))
    }

    func testFastHorizontalFlickUsesPredictedEnd() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: -35, height: 3),
            predictedEndTranslation: CGSize(width: -90, height: 7)
        ))
    }

    func testIndicatorStaysHiddenUntilActivationDistance() {
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: -20, height: 0)),
            0
        )
        XCTAssertLessThan(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: -24, height: 0)),
            0
        )
    }

    func testVisualOffsetIsCapped() {
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: true, translation: CGSize(width: -500, height: 0)),
            -MessageReplySwipePolicy.maximumOffset
        )
    }

    func testCanLockRequiresClearHorizontalStart() {
        XCTAssertTrue(MessageReplySwipePolicy.canLock(CGSize(width: -24, height: 10)))
        XCTAssertTrue(MessageReplySwipePolicy.canLock(CGSize(width: 24, height: 10)))
        XCTAssertFalse(MessageReplySwipePolicy.canLock(CGSize(width: -30, height: 20)))
        XCTAssertFalse(MessageReplySwipePolicy.canLock(CGSize(width: -8, height: 5)))
        XCTAssertTrue(MessageReplySwipePolicy.canLock(CGSize(width: 40, height: 4)))
    }

    func testCanLockIsUnavailableOnceTheGestureTurnsVertical() {
        // A scroll that arcs left after travelling down must never lock the
        // swipe: the vertical travel already exceeds the lock budget.
        XCTAssertFalse(MessageReplySwipePolicy.canLock(CGSize(width: -30, height: 40)))
        XCTAssertFalse(MessageReplySwipePolicy.canLock(CGSize(width: -80, height: 60)))
    }

    func testLockedSwipeToleratesVerticalDrift() {
        // Once locked the finger may drift: a 1.17 ratio would be rejected
        // by the 1.6 lock dominance but must still count as a reply swipe.
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            locked: true,
            translation: CGSize(width: -70, height: 60),
            predictedEndTranslation: CGSize(width: -70, height: 60)
        ))
        XCTAssertLessThan(
            MessageReplySwipePolicy.offset(locked: true, translation: CGSize(width: -70, height: 60)),
            0
        )
    }

    func testRightwardDiagonalScrollDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            locked: false,
            translation: CGSize(width: 54, height: 44),
            predictedEndTranslation: CGSize(width: 76, height: 58)
        ))
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: 54, height: 44)),
            0
        )
    }

    func testRightwardVisualOffsetIsCapped() {
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: true, translation: CGSize(width: 500, height: 0)),
            MessageReplySwipePolicy.maximumOffset
        )
    }

    func testRightwardIndicatorStaysHiddenUntilActivationDistance() {
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: 20, height: 0)),
            0
        )
        XCTAssertGreaterThan(
            MessageReplySwipePolicy.offset(locked: false, translation: CGSize(width: 24, height: 0)),
            0
        )
    }

    func testRightwardLockedSwipeToleratesVerticalDrift() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            locked: true,
            translation: CGSize(width: 70, height: 60),
            predictedEndTranslation: CGSize(width: 70, height: 60)
        ))
        XCTAssertGreaterThan(
            MessageReplySwipePolicy.offset(locked: true, translation: CGSize(width: 70, height: 60)),
            0
        )
    }
}


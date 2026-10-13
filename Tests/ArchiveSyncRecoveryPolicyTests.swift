import XCTest
@testable import Luma

final class ArchiveSyncRecoveryPolicyTests: XCTestCase {
    func testIncrementalOverlapDoesNotReplaySeveralMinutesPerPass() {
        XCTAssertEqual(ArchiveSyncRecoveryPolicy.incrementalOverlap, 60)
    }

    func testQueryTimeoutIsFinite() {
        XCTAssertGreaterThan(ArchiveSyncRecoveryPolicy.queryTimeoutNanoseconds, 0)
        XCTAssertLessThanOrEqual(
            ArchiveSyncRecoveryPolicy.queryTimeoutNanoseconds,
            20_000_000_000
        )
    }

    func testPageApplicationAlsoHasAFiniteWatchdog() {
        XCTAssertGreaterThan(ArchiveSyncRecoveryPolicy.pageApplyTimeoutNanoseconds, 0)
        XCTAssertLessThanOrEqual(
            ArchiveSyncRecoveryPolicy.pageApplyTimeoutNanoseconds,
            ArchiveSyncRecoveryPolicy.queryTimeoutNanoseconds
        )
    }

    func testFailedPagesHaveAtMostOneAutomaticRetry() {
        XCTAssertEqual(ArchiveSyncRecoveryPolicy.pageRetryLimit, 1)
    }

    func testCatchUpRetryDelayAndCapAreBounded() {
        XCTAssertGreaterThan(
            ArchiveSyncRecoveryPolicy.retryAfterFailureDelayNanoseconds,
            0
        )
        XCTAssertGreaterThan(ArchiveSyncRecoveryPolicy.maximumAutomaticRetries, 0)
        XCTAssertLessThanOrEqual(ArchiveSyncRecoveryPolicy.maximumAutomaticRetries, 5)
    }

    func testCaptureResumeDelayLetsCameraReleaseResources() {
        XCTAssertGreaterThan(
            ArchiveSyncRecoveryPolicy.resumeAfterCaptureDelayNanoseconds,
            ArchiveSyncRecoveryPolicy.interPageDelayNanoseconds
        )
    }
}

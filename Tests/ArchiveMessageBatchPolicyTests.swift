import XCTest
@testable import Luma

final class ArchiveMessageBatchPolicyTests: XCTestCase {
    func testInteractivePageSize() {
        XCTAssertEqual(ArchiveMessageBatchPolicy.pageSize, 40)
    }

    func testStanzasAreDecodedInSmallBatchesPerMainActorSlice() {
        XCTAssertGreaterThan(ArchiveMessageBatchPolicy.decodeSliceSize, 0)
        XCTAssertLessThanOrEqual(ArchiveMessageBatchPolicy.decodeSliceSize, 16)
        XCTAssertGreaterThan(ArchiveMessageBatchPolicy.interSliceDelayNanoseconds, 0)
    }

    func testInboxCanHoldAProtocolViolatingDoublePageWithoutGrowingForever() {
        XCTAssertGreaterThanOrEqual(
            ArchiveMessageBatchPolicy.maximumBufferedStanzas,
            ArchiveMessageBatchPolicy.pageSize * 2
        )
        XCTAssertLessThanOrEqual(ArchiveMessageBatchPolicy.maximumBufferedStanzas, 128)
    }
}

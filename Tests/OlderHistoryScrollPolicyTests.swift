import XCTest
@testable import Luma

final class OlderHistoryScrollPolicyTests: XCTestCase {
    func testIncompletePageWithFirstCursorContinues() {
        let page = OlderHistoryScrollPolicy.page(
            complete: false,
            pageFirstID: " mam-17 "
        )

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBefore, "mam-17")
    }

    func testCompletePageStopsEvenWithCursor() {
        let page = OlderHistoryScrollPolicy.page(
            complete: true,
            pageFirstID: "mam-17"
        )

        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.nextBefore, "mam-17")
    }

    func testEmptyPageNeverReportsMore() {
        // A server that keeps answering without RSM <first> must not leave
        // the UI re-requesting the same page in a spinner loop.
        let page = OlderHistoryScrollPolicy.page(complete: false, pageFirstID: nil)

        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextBefore)
    }

    func testWhitespaceOnlyCursorIsDiscarded() {
        let page = OlderHistoryScrollPolicy.page(complete: false, pageFirstID: "   ")

        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextBefore)
    }

    func testPageFirstIDMustNotBecomeAnEmptyCursor() {
        let page = OlderHistoryScrollPolicy.page(complete: false, pageFirstID: "")

        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextBefore)
    }
}

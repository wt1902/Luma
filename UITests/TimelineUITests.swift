import XCTest

final class TimelineUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-luma-ui-test-chat"]
        app.launch()
        return app
    }

    private func bubble(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "bubble-\(id)").firstMatch
    }

    private func openChat(_ app: XCUIApplication) {
        let chatRow = app.staticTexts["uitest-peer"]
        XCTAssertTrue(chatRow.waitForExistence(timeout: 30))
        chatRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "chat-timeline").firstMatch
                .waitForExistence(timeout: 30)
        )
        XCTAssertTrue(bubble("uitest-msg-60", in: app).waitForExistence(timeout: 30))
    }

    func testTimelineVerticalScrollWorks() throws {
        let app = launchApp()
        openChat(app)

        for _ in 0..<7 {
            app.swipeDown()
        }
        XCTAssertTrue(bubble("uitest-msg-1", in: app).waitForExistence(timeout: 10))

        for _ in 0..<9 {
            app.swipeUp()
        }
        XCTAssertTrue(bubble("uitest-msg-60", in: app).waitForExistence(timeout: 10))
    }

    func testReplySwipeShowsPlateAndScrollStillWorks() throws {
        let app = launchApp()
        openChat(app)

        // The initial scroll position varies slightly between runs, so pick
        // the first hittable bubble from the bottom area of the timeline.
        let candidates = [60, 59, 58, 55, 50, 45].map {
            bubble("uitest-msg-\($0)", in: app)
        }
        // A controlled right-to-left drag: the stock swipeLeft() flicks too
        // fast for the gesture's horizontal lock to engage reliably. The drag
        // itself can occasionally be swallowed, so retry on the next hittable
        // bubble until the reply plate appears.
        let banner = app.descendants(matching: .any).matching(identifier: "reply-banner").firstMatch
        var bannerAppeared = false
        for _ in 0..<3 where !bannerAppeared {
            guard let target = candidates.first(where: { $0.exists && $0.isHittable }) else {
                break
            }
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
            bannerAppeared = banner.waitForExistence(timeout: 2)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "after-drag"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(bannerAppeared, "A left swipe must open the reply plate")

        app.buttons["Отменить ответ"].tap()
        for _ in 0..<7 {
            app.swipeDown()
        }
        XCTAssertTrue(bubble("uitest-msg-1", in: app).waitForExistence(timeout: 10))
    }
}


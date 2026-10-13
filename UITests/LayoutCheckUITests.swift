import XCTest

/// Layout regression checks: the inline search fields must live at the top
/// of the Chats and Contacts tabs, above the lists (they used to be pushed
/// to the bottom when implemented via `.searchable`).
final class LayoutCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-luma-ui-test-chat"]
        app.launch()
        return app
    }

    func testChatsAndContactsSearchFieldsAreAtTop() throws {
        let app = launchApp()
        dismissAnyAlert(app)

        // Keep the clean screen on display long enough for external
        // `simctl io screenshot` captures of the tab bar.
        Thread.sleep(forTimeInterval: 12)

        // The Telegram-style tabs render `.searchable` fields as
        // XCUIElementTypeSearchField (a TextField subtype in newer runtimes,
        // but queried as `searchFields` on the iOS 26 simulator).
        let chatSearch = app.searchFields["Поиск чатов"]
        XCTAssertTrue(chatSearch.waitForExistence(timeout: 30))
        addScreenshot(named: "chats-search-top", app: app)

        let chatRow = app.staticTexts["uitest-peer"]
        XCTAssertTrue(chatRow.waitForExistence(timeout: 15))
        XCTAssertLessThan(
            chatSearch.frame.midY,
            chatRow.frame.midY,
            "The chats search field must sit above the chat list"
        )

        app.buttons["Контакты"].tap()

        let contactSearch = app.searchFields["Поиск контактов"]
        XCTAssertTrue(contactSearch.waitForExistence(timeout: 15))
        XCTAssertLessThan(
            contactSearch.frame.minY,
            app.frame.height * 0.4,
            "The contacts search field must sit near the top of the screen"
        )
        addScreenshot(named: "contacts-search-top", app: app)
    }

    func testTabBarHidesInsideChat() throws {
        let app = launchApp()
        dismissAnyAlert(app)

        let chatRow = app.staticTexts["uitest-peer"]
        XCTAssertTrue(chatRow.waitForExistence(timeout: 30))
        chatRow.tap()

        let timeline = app.descendants(matching: .any).matching(identifier: "chat-timeline").firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 30))

        // A pushed conversation takes the whole screen: no tab bar.
        let tabBar = app.tabBars.firstMatch
        XCTAssertFalse(tabBar.exists, "The tab bar must be hidden inside a chat")

        // Popping back to the list restores the tab bar.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
    }

    private func addScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The unsigned debug build can present a system "missing rights" alert
    /// on the simulator; dismiss it so it does not cover the UI.
    private func dismissAnyAlert(_ app: XCUIApplication) {
        let hosts = [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        for host in hosts {
            let ok = host.alerts.buttons["OK"]
            if ok.waitForExistence(timeout: 8) {
                ok.tap()
                return
            }
        }
    }
}

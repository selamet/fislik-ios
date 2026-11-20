import XCTest

/// Detected subscriptions against the demo server: turn one into a recurring
/// expense, dismiss another and bring it back.
final class SubscriptionFlow: XCTestCase {
    func testTrackDismissAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-open", "reports"]
        app.launch()

        let track = app.buttons["track-ds3"]
        XCTAssertTrue(track.waitForExistence(timeout: 15), "subscriptions are listed")
        app.scrollToMiddle(track)
        track.tap()
        XCTAssertTrue(app.staticTexts["Tekrarlayan gidere çevrilsin mi?"].waitForExistence(timeout: 15))
        // The dialog's button has the same title as the row buttons; take the one not in the list.
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'track-')", "Tekrarlayana çevir")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        confirm.tap()
        XCTAssertTrue(app.buttons["track-ds3"].waitForNonExistence(timeout: 15), "the tracked one leaves the list")

        let dismiss = app.buttons["dismiss-ds2"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15))
        app.scrollToMiddle(dismiss)
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 15), "the dismissed one is hidden")
        let restore = app.buttons["Gizlenenleri geri getir (1)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 15))
        app.scrollToMiddle(restore)
        restore.tap()
        XCTAssertTrue(app.buttons["dismiss-ds2"].waitForExistence(timeout: 15), "it comes back")
    }
}

import XCTest

/// Statement comparison against the demo server: book a missing line as an
/// expense and ignore another.
final class StatementFlow: XCTestCase {
    func testSettleTheLinesOfAStatement() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-open", "statements"]
        app.launch()

        let book = app.buttons["book-sl3"]
        XCTAssertTrue(book.waitForExistence(timeout: 15), "missing lines offer booking")
        // The plan arrives separately and swaps the upload button for a note;
        // wait for that so the layout no longer moves under the tap.
        XCTAssertTrue(app.staticTexts["statement-plan-note"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["4 harcamadan 2 tanesinin fişi eksik."].exists)
        book.tap()
        let confirm = app.buttons["confirm-book"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "the booking sheet opens")
        app.buttons["book-category"].tap()
        app.buttons["Abonelik ve yazılım"].tap()
        confirm.tap()
        XCTAssertTrue(app.staticTexts["4 harcamadan 1 tanesinin fişi eksik."].waitForExistence(timeout: 15))

        app.buttons["ignore-sl2"].tap()
        XCTAssertTrue(app.staticTexts["4 harcamanın hepsi karşılandı."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Fişi eksik harcama kalmadı."].exists)
        // The demo company is on the free plan: no upload, a note instead.
        XCTAssertFalse(app.buttons["upload-statement"].exists)
    }

    func testUploadOpensTheFilePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-demoPlan", "pro", "-appearance", "light", "-open", "statements"]
        app.launch()
        let upload = app.buttons["upload-statement"]
        XCTAssertTrue(upload.waitForExistence(timeout: 15))
        upload.tap()
        // The system document picker brings its own Cancel button.
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Vazgeç", "İptal"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "the file picker opens")
        cancel.tap()
    }
}

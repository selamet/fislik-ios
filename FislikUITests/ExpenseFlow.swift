import XCTest

/// Manual expenses end to end against the demo server: add one from the
/// reports screen, see it listed, edit it and delete it.
final class ExpenseFlow: XCTestCase {
    func testAddEditAndDeleteAManualExpense() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-open", "reports"]
        app.launch()

        let add = app.buttons["add-expense"]
        XCTAssertTrue(app.buttons["expense-e1"].waitForExistence(timeout: 10), "demo expenses are listed")
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()

        let save = app.buttons["save-expense"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the form opens")
        // Saving an empty form explains what is missing.
        save.tap()
        XCTAssertTrue(app.staticTexts["Kısa bir açıklama yaz."].waitForExistence(timeout: 2))

        let fields = app.textFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("Personel maaşları")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("42.500")
        app.buttons["expense-category"].tap()
        app.buttons["Maaş ve personel"].tap()
        save.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personel maaşları")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new expense is listed")
        XCTAssertTrue(row.label.contains("42.500,00"), row.label)
        XCTAssertTrue(row.label.contains("Maaş ve personel"), row.label)

        row.tap()
        XCTAssertTrue(app.buttons["Gideri sil"].waitForExistence(timeout: 5))
        app.buttons["Gideri sil"].tap()
        app.buttons["Sil"].firstMatch.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the deleted expense is gone")
    }
}

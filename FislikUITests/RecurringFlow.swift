import XCTest

/// Recurring expenses against the demo server: add a rule and see it listed.
final class RecurringFlow: XCTestCase {
    func testAddARecurringExpense() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-open", "reports"]
        app.launch()

        let add = app.buttons["add-recurring"]
        XCTAssertTrue(app.buttons["recurring-rr1"].waitForExistence(timeout: 10), "demo rules are listed")
        app.scrollToMiddle(add)
        add.tap()

        let save = app.buttons["save-recurring"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "the form opens")
        // Menus first: the number pad would cover them.
        app.buttons["recurring-day"].tap()
        XCTAssertTrue(app.buttons["15"].waitForExistence(timeout: 15))
        app.buttons["15"].tap()
        app.buttons["recurring-category"].tap()
        XCTAssertTrue(app.buttons["Abonelik ve yazılım"].waitForExistence(timeout: 15))
        app.buttons["Abonelik ve yazılım"].tap()
        let fields = app.textFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("Muhasebe ücreti")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("3.000")
        save.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Muhasebe ücreti")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the new rule is listed")
        XCTAssertTrue(row.label.contains("Her ayın 15. günü"), row.label)
        XCTAssertTrue(row.label.contains("3.000,00"), row.label)
    }
}

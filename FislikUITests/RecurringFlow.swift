import XCTest

/// Recurring expenses against the demo server: add a rule and see it listed.
final class RecurringFlow: XCTestCase {
    func testAddARecurringExpense() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-open", "reports"]
        app.launch()

        let add = app.buttons["add-recurring"]
        XCTAssertTrue(app.buttons["recurring-rr1"].waitForExistence(timeout: 10), "demo rules are listed")
        for _ in 0..<6 where !add.isHittable { app.swipeUp(velocity: .slow) }
        Thread.sleep(forTimeInterval: 1.5) // let the scroll settle before tapping
        add.tap()

        let save = app.buttons["save-recurring"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "the form opens")
        let fields = app.textFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("Muhasebe ücreti")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("3.000")
        app.buttons["recurring-day"].tap()
        app.buttons["15"].tap()
        app.buttons["recurring-category"].tap()
        app.buttons["Abonelik ve yazılım"].tap()
        save.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Muhasebe ücreti")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the new rule is listed")
        XCTAssertTrue(row.label.contains("Her ayın 15. günü"), row.label)
        XCTAssertTrue(row.label.contains("3.000,00"), row.label)
    }
}

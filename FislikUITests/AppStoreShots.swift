import XCTest

/// App Store screenshots (run on iPhone 17 Pro Max for 6.9" / 1320×2868).
/// `TEST_RUNNER_SCREENSHOT_DIR=/path xcodebuild test -only-testing:FislikUITests/AppStoreShots`
final class AppStoreShots: XCTestCase {
    private var app: XCUIApplication!

    private func save(_ name: String, wait: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: wait)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func tap(_ predicate: NSPredicate, in query: XCUIElementQuery) {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            for i in 0..<min(query.matching(predicate).count, 20) {
                let el = query.matching(predicate).element(boundBy: i)
                if el.exists && el.isHittable { el.tap(); return }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
    }

    private func tap(_ label: String) { tap(NSPredicate(format: "label == %@", label), in: app.descendants(matching: .any)) }
    private func tapContaining(_ text: String) { tap(NSPredicate(format: "label CONTAINS %@", text), in: app.buttons) }

    func testClientShots() {
        app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "client", "-appearance", "light", "-demoPeriod", "2026-10"]
        app.launch()
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Migros")).firstMatch.waitForExistence(timeout: 10)
        save("01-home", wait: 2)
        tapContaining("Trendyol")
        save("02-detail")
        tap("Fişler")
        tap("Fiş ekle")
        save("03-add")
        tap("Kapat")
        Thread.sleep(forTimeInterval: 1)
        tap("Muhasebeciye gönder")
        save("04-send", wait: 2)
        tap("Kapat")
        Thread.sleep(forTimeInterval: 1)
        tap("Bildirimler")
        save("05-notifications")
    }

    func testAccountantShots() {
        app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "accountant", "-appearance", "light", "-demoPeriod", "2026-10"]
        app.launch()
        let row = app.staticTexts["Mehmet Demir"]
        _ = row.waitForExistence(timeout: 10)
        save("06-clients", wait: 2)
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Ayşe Yıldırım")).element(boundBy: 0).tap()
        save("07-client-month", wait: 2)
    }
}

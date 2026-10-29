import XCTest

/// Walks every main screen in demo mode and saves screenshots.
/// Run with `TEST_RUNNER_SCREENSHOT_DIR=/path xcodebuild test -only-testing:FislikUITests`.
final class ScreenTour: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = ""

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
    }

    private func shot(_ name: String, wait: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: wait)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)\(name).png"))
        }
    }

    /// Taps the first *hittable* match; hidden tabs keep their elements in the tree.
    private func tapFirst(_ query: XCUIElementQuery, _ what: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for i in 0..<min(query.count, 30) {
                let el = query.element(boundBy: i)
                if el.exists && el.isHittable { el.tap(); return }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        XCTFail("missing \(what)")
    }

    private func tap(_ label: String, timeout: TimeInterval = 4) {
        tapFirst(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)), label, timeout: timeout)
    }

    private func tapContaining(_ text: String, timeout: TimeInterval = 4) {
        tapFirst(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)), "button containing \(text)", timeout: timeout)
    }

    private func back() {
        let q = app.buttons.matching(NSPredicate(format: "label IN %@", ["Fişler", "Profil", "Geri", "Mükellefler", "Giriş"]))
        for i in 0..<q.count where q.element(boundBy: i).isHittable {
            q.element(boundBy: i).tap()
            return
        }
    }

    private func dismissSheet() {
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.6)
    }

    func testAuthScreens() {
        prefix = "a-"
        launch(["-reset"])
        shot("01-onboarding", wait: 2)
        tap("Giriş yap")
        shot("02-login")
        tap("Kayıt ol")
        shot("03-register")
        back()
        tap("Şifremi unuttum")
        shot("04-forgot")
    }

    func testClientScreens() {
        for mode in ["light", "dark"] {
            prefix = "c-\(mode)-"
            launch(["-demo", "client", "-appearance", mode])
            shot("01-home-grid", wait: 3)
            app.swipeUp()
            shot("02-home-grid-scrolled")
            app.swipeDown()
            tap("Liste görünümü")
            shot("03-home-list")
            tap("Kart görünümü")
            tapContaining("Sorunlu")
            shot("04-filter-issues")
            tapContaining("Tümü")

            tapContaining("Trendyol")
            shot("05-detail-issue", wait: 1.5)
            app.swipeUp()
            shot("06-detail-fields")
            tap("Düzelt")
            shot("07-edit", wait: 1.5)
            tap("Vazgeç")
            tap("Yeniden analiz et")
            shot("08-reanalyze-dialog")
            tap("Vazgeç")
            tap("Fişi sil")
            shot("09-delete-dialog")
            tap("Vazgeç")
            back()

            tapContaining("Starbucks")
            shot("10-detail-wrong-month", wait: 1.5)
            back()
            app.swipeUp()
            tapContaining("Türk Telekom")
            shot("11-detail-pdf", wait: 2)
            back()
            app.swipeDown()

            tap("Ara")
            shot("12-search")
            app.typeText("mig")
            shot("13-search-results", wait: 2)
            tap("Vazgeç")

            tap("Fiş ekle")
            shot("14-add-sheet")
            dismissSheet()
            tap("Muhasebeciye gönder")
            shot("15-submit-sheet", wait: 1.5)
            dismissSheet()

            tap("Önceki ay")
            shot("16-prev-month", wait: 1.5)
            tap("Önceki ay")
            shot("17-locked-month", wait: 1.5)
            tap("Önceki ay")
            shot("18-empty-month", wait: 1.5)

            tap("Muhasebecim")
            shot("19-accountant", wait: 1.5)
            tap("Davet et")
            shot("20-invite-sheet")
            dismissSheet()

            tap("Bildirimler")
            shot("21-notifications", wait: 1.5)

            tap("Profil")
            shot("22-profile", wait: 1.5)
            tapContaining("Analiz kredisi")
            shot("23-credits")
            back()
            tap("Bildirim tercihleri")
            shot("24-prefs")
            back()
            tap("Firma bilgileri")
            shot("25-company", wait: 1.5)
            app.terminate()
        }
    }

    func testAccountantScreens() {
        prefix = "x-"
        launch(["-demo", "accountant", "-appearance", "light"])
        shot("01-clients", wait: 3)
        tapContaining("Ayşe Yıldırım")
        shot("02-client-month", wait: 2)
        tap("Seç")
        tapContaining("A101")
        tapContaining("Starbucks")
        shot("03-selecting")
        tap("Vazgeç")
        tap("Dışa aktar")
        shot("04-export", wait: 1.5)
        dismissSheet()
        tap("Ayı kapat")
        shot("05-lock-dialog")
        tap("Vazgeç")
        tapContaining("Trendyol")
        shot("06-acc-detail", wait: 1.5)
        back()
        back()
        tap("Bildirimler")
        shot("07-acc-notifications", wait: 1.5)
        tap("Profil")
        shot("08-acc-profile", wait: 1.5)
    }
}

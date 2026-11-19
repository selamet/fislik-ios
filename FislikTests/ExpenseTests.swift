import XCTest
@testable import Fislik

final class ExpenseTests: XCTestCase {
    private let istanbul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    func testReadsTurkishAmounts() {
        XCTAssertEqual(Money.parse("15.000"), Decimal(15000))
        XCTAssertEqual(Money.parse("1.250.000"), Decimal(1_250_000))
        XCTAssertEqual(Money.parse("1.250,50"), Decimal(string: "1250.50"))
        XCTAssertEqual(Money.parse("₺ 1250.5"), Decimal(string: "1250.5"))
        XCTAssertEqual(Money.parse("15.000,00"), Decimal(15000))
        XCTAssertNil(Money.parse("12,345"))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse(""))
    }

    func testDaysKeepTheCalendarDayPicked() {
        // Just after midnight in Istanbul is still the previous day in UTC.
        let picked = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 30))!
        XCTAssertEqual(ExpenseDay.string(picked, calendar: istanbul), "2026-10-05")
        let back = ExpenseDay.date("2026-10-05", calendar: istanbul)!
        XCTAssertEqual(ExpenseDay.string(back, calendar: istanbul), "2026-10-05")
        XCTAssertEqual(ExpenseDay.label("2026-10-05"), "5 Ekim 2026")
    }

    func testDefaultDateIsTodayOnlyInTheCurrentMonth() {
        let now = istanbul.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        let current = Period(year: 2026, month: 11), earlier = Period(year: 2026, month: 9)
        XCTAssertEqual(ExpenseDay.string(ExpenseDay.defaultDate(for: current, now: now, calendar: istanbul), calendar: istanbul), "2026-11-19")
        XCTAssertEqual(ExpenseDay.string(ExpenseDay.defaultDate(for: earlier, now: now, calendar: istanbul), calendar: istanbul), "2026-09-01")
    }

    func testValidDraftBecomesTheRequestBody() throws {
        var draft = ExpenseDraft(period: Period(year: 2026, month: 10))
        draft.description = "  Ofis   kirası "
        draft.amount = "15.000"
        draft.vat = "2.500,00"
        draft.category = "kira"
        draft.date = ExpenseDay.date("2026-10-01")!
        let body = try draft.validated().get()
        XCTAssertEqual(body, ExpenseBody(expenseDate: "2026-10-01", amount: 15000, vatAmount: 2500, category: "kira", description: "Ofis kirası"))

        let sent = try JSONSerialization.jsonObject(with: APIClient.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(sent?["expense_date"] as? String, "2026-10-01")
        XCTAssertEqual((sent?["amount"] as? NSNumber)?.decimalValue, 15000)

        draft.vat = ""
        let noVat = try JSONSerialization.jsonObject(with: APIClient.encoder.encode(try draft.validated().get())) as? [String: Any]
        XCTAssertTrue(noVat?["vat_amount"] is NSNull, "an edit must be able to clear VAT")
    }

    func testInvalidDraftNamesEachProblem() {
        var draft = ExpenseDraft(period: Period(year: 2026, month: 10))
        draft.amount = "0"
        draft.vat = "x"
        guard case .failure(let errors) = draft.validated() else { return XCTFail("should fail") }
        XCTAssertEqual(errors.description, "Kısa bir açıklama yaz.")
        XCTAssertEqual(errors.amount, "Sıfırdan büyük bir tutar gir (ör. 1.250,50).")
        XCTAssertEqual(errors.vat, "KDV tutarı geçersiz.")

        draft.description = "Kira"
        draft.amount = "100"
        draft.vat = "150"
        guard case .failure(let vatErrors) = draft.validated() else { return XCTFail("should fail") }
        XCTAssertEqual(vatErrors, ExpenseDraft.Errors(vat: "KDV tutardan büyük olamaz."))
    }

    func testDecodesAnExpenseAndPrefillsTheForm() throws {
        let json = """
        [{"id": "e1", "period": "2026-10", "expense_date": "2026-10-01", "amount": "15000.00", "vat_amount": null,
          "category": "kira", "description": "Ofis kirası", "created_by_name": "Ayşe", "created_at": "2026-10-01T09:00:00Z",
          "recurring": true}]
        """
        let expense = try APIClient.decoder.decode([Expense].self, from: DecimalNormalizer.normalize(Data(json.utf8)))[0]
        XCTAssertEqual(expense.amount, 15000)
        XCTAssertNil(expense.vatAmount)
        XCTAssertTrue(expense.isRecurring)
        XCTAssertEqual(expense.dateLabel, "1 Ekim 2026")
        let draft = ExpenseDraft(expense)
        XCTAssertEqual(draft.amount, "15.000,00")
        XCTAssertEqual(draft.vat, "")
        XCTAssertEqual(try draft.validated().get().amount, 15000)
    }
}

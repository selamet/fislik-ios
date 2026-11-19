import XCTest
@testable import Fislik

final class RecurringExpenseTests: XCTestCase {
    private let json = """
    [{"id": "r1", "description": "Ofis kirası", "amount": "15000.00", "vat_amount": "2500.00", "category": "kira",
      "day_of_month": 5, "end_period": null, "active": true, "last_generated_period": "2026-10", "generating": true},
     {"id": "r2", "description": "Leasing", "amount": "8750.00", "vat_amount": null, "category": "ulasim",
      "day_of_month": 31, "end_period": "2027-03", "active": false, "last_generated_period": null, "generating": false}]
    """

    func testDecodesRulesAndDescribesTheirSchedule() throws {
        let rules = try APIClient.decoder.decode([RecurringExpense].self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertEqual(rules[0].amount, 15000)
        XCTAssertEqual(rules[0].vatAmount, 2500)
        XCTAssertEqual(rules[0].schedule, "Her ayın 5. günü")
        XCTAssertEqual(rules[1].schedule, "Her ayın 31. günü (kısa aylarda son gün) · Mart 2027 sonuna kadar")
        XCTAssertNil(rules[0].note(paid: true))
        XCTAssertEqual(rules[0].note(paid: false), "Ücretsiz planda çalışmaz")
        XCTAssertEqual(rules[1].note(paid: true), "Duraklatıldı")
    }

    func testDraftRoundTripsARuleAndSendsExplicitNulls() throws {
        let rule = try APIClient.decoder.decode([RecurringExpense].self, from: DecimalNormalizer.normalize(Data(json.utf8)))[1]
        var draft = RecurringDraft(rule)
        XCTAssertEqual(draft.amount, "8.750,00")
        XCTAssertEqual(draft.endPeriod, Period(year: 2027, month: 3))
        draft.endPeriod = nil
        let body = try draft.validated().get()
        XCTAssertEqual(body, RecurringBody(description: "Leasing", amount: 8750, vatAmount: nil, category: "ulasim", dayOfMonth: 31, endPeriod: nil))
        let sent = try JSONSerialization.jsonObject(with: APIClient.encoder.encode(body)) as? [String: Any]
        XCTAssertTrue(sent?["end_period"] is NSNull)
        XCTAssertTrue(sent?["vat_amount"] is NSNull)
        XCTAssertEqual(sent?["day_of_month"] as? Int, 31)
    }

    func testInvalidDraftNamesEachProblem() {
        var draft = RecurringDraft()
        draft.amount = "abc"
        guard case .failure(let errors) = draft.validated() else { return XCTFail("should fail") }
        XCTAssertEqual(errors.description, "Kısa bir açıklama yaz.")
        XCTAssertNotNil(errors.amount)
        draft.description = "Kira"
        draft.amount = "100"
        draft.vat = "101"
        guard case .failure(let vat) = draft.validated() else { return XCTFail("should fail") }
        XCTAssertEqual(vat.vat, "KDV tutardan büyük olamaz.")
    }

    func testEndChoicesCoverTwoYearsFromThisMonth() {
        let choices = RecurringDraft.endChoices(from: Period(year: 2026, month: 11))
        XCTAssertEqual(choices.count, 24)
        XCTAssertEqual(choices.first?.raw, "2026-11")
        XCTAssertEqual(choices.last?.raw, "2028-10")
    }
}

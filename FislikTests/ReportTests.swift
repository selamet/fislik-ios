import XCTest
@testable import Fislik

final class ReportTests: XCTestCase {
    private func decode(_ json: String) throws -> MonthlyReport {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MonthlyReport.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
    }

    private let paid = """
    {"period": "2026-10", "scope": "company", "detailed": true,
     "totals": {"receipt_count": 5, "analyzed_count": 4, "total_amount": "1680.50", "vat_total": "267.55"},
     "category_totals": {"market": "80.00", "yakit": "1600.50"},
     "payment_method_totals": {"kredi_karti": "1200.00", "nakit": "400.50", "bilinmiyor": "80.00"},
     "members": [
       {"user_id": "u1", "name": "Owner", "kind": "member", "receipt_count": 1, "total_amount": "1200.00", "vat_total": "200.00"},
       {"user_id": null, "name": "Eski üye", "kind": "member", "receipt_count": 3, "total_amount": "480.50", "vat_total": "67.55"},
       {"user_id": "a1", "name": "Mali Müşavir", "kind": "accountant", "receipt_count": 1, "total_amount": "0", "vat_total": "0"}],
     "merchants": [
       {"name": "Shell", "receipt_count": 3, "total_amount": "1600.50"},
       {"name": null, "receipt_count": 1, "total_amount": "80.00"}],
     "previous": {"period": "2026-09", "receipt_count": 2, "analyzed_count": 2, "total_amount": "840.25", "vat_total": "100.00"},
     "trend": [
       {"period": "2026-09", "receipt_count": 2, "analyzed_count": 2, "total_amount": "840.25", "vat_total": "100.00"},
       {"period": "2026-10", "receipt_count": 5, "analyzed_count": 4, "total_amount": "1680.50", "vat_total": "267.55"}]}
    """

    private let free = """
    {"period": "2026-10", "scope": "own", "detailed": false,
     "totals": {"receipt_count": 0, "analyzed_count": 0, "total_amount": "0", "vat_total": "0"},
     "category_totals": {}, "payment_method_totals": {},
     "members": [], "merchants": [], "previous": null, "trend": []}
    """

    func testDecodesPaidReportWithExactAmounts() throws {
        let report = try decode(paid)
        XCTAssertEqual(report.totals.totalAmount, Decimal(string: "1680.50"))
        XCTAssertEqual(report.totals.vatTotal, Decimal(string: "267.55"))
        XCTAssertEqual(report.totals.waitingCount, 1)
        XCTAssertTrue(report.detailed)
        XCTAssertFalse(report.isOwnScope)
        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.members.map(\.name), ["Owner", "Eski üye", "Mali Müşavir"])
        XCTAssertEqual(report.members.map(\.isAccountant), [false, false, true])
        XCTAssertEqual(report.members.map(\.id), ["u1", "Eski üye", "a1"])
        XCTAssertEqual(report.merchants.map(\.label), ["Shell", "Satıcısı okunamayan fişler"])
        XCTAssertEqual(report.previous?.title, "Eylül 2026")
        XCTAssertEqual(report.trend.map(\.shortMonth), ["Eyl", "Eki"])
    }

    func testDecodesFreeReportWithoutDetails() throws {
        let report = try decode(free)
        XCTAssertFalse(report.detailed)
        XCTAssertTrue(report.isOwnScope)
        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.previous)
        XCTAssertNil(report.changePercent)
        XCTAssertTrue(report.categories.isEmpty)
    }

    func testBreakdownsAreLabelledAndSortedLargestFirst() throws {
        let report = try decode(paid)
        XCTAssertEqual(report.categories.map(\.label), ["Yakıt", "Market"])
        XCTAssertEqual(report.paymentMethods.map(\.label), ["Kredi Kartı", "Nakit", "Bilinmiyor"])
        XCTAssertEqual(report.categories.first?.amount, Decimal(string: "1600.50"))
    }

    func testChangeAgainstPreviousMonth() throws {
        var report = try decode(paid)
        XCTAssertEqual(report.changePercent, 100)
        report.totals.totalAmount = Decimal(string: "420.12")!
        XCTAssertEqual(report.changePercent, -50)
        report.previous?.totalAmount = 0
        XCTAssertNil(report.changePercent)
        XCTAssertEqual(ReportMath.signedPercent(39), "+%39")
        XCTAssertEqual(ReportMath.signedPercent(-12), "−%12")
        XCTAssertEqual(ReportMath.signedPercent(0), "%0")
    }

    func testShareAndTrendHeights() throws {
        XCTAssertEqual(ReportMath.share(25, of: 100), 0.25)
        XCTAssertEqual(ReportMath.share(10, of: 0), 0)
        XCTAssertEqual(ReportMath.share(150, of: 100), 1)
        XCTAssertEqual(ReportMath.percent(0.254), "%25")
        let report = try decode(paid)
        let heights = ReportMath.heights(report.trend)
        XCTAssertEqual(heights[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(heights[1], 1)
        XCTAssertEqual(ReportMath.heights([]), [])
    }
}


final class ReportManualExpenseTests: XCTestCase {
    private func decode(_ json: String) throws -> MonthlyReport {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MonthlyReport.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
    }

    private let manualOnly = """
    {"period": "2026-10", "scope": "company", "detailed": false,
     "totals": {"receipt_count": 0, "analyzed_count": 0, "total_amount": "15000.00", "vat_total": "0",
                "manual_count": 2, "manual_amount": "15000.50"},
     "category_totals": {"kira": "15000.00", "abonelik": "0.50"}, "payment_method_totals": {},
     "members": [], "merchants": [], "previous": null, "trend": []}
    """

    func testAMonthWithOnlyManualExpensesIsNotEmpty() throws {
        let report = try decode(manualOnly)
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.totals.hasManual)
        XCTAssertEqual(report.totals.manualCount, 2)
        XCTAssertEqual(report.totals.manualAmount, Decimal(string: "15000.50"))
    }

    func testNewCategoriesHaveLabels() throws {
        let report = try decode(manualOnly)
        XCTAssertEqual(report.categories.map(\.label), ["Kira", "Abonelik ve yazılım"])
        XCTAssertEqual(CategoryLabels.label("maas"), "Maaş ve personel")
        XCTAssertEqual(CategoryLabels.label("yakit"), "Yakıt")
        XCTAssertEqual(CategoryLabels.label("bilinmeyen"), "bilinmeyen")
        XCTAssertEqual(CategoryLabels.all.count, 16)
    }

    func testOlderAPIsWithoutManualFieldsStillDecode() throws {
        let older = """
        {"period": "2026-10", "scope": "company", "detailed": false,
         "totals": {"receipt_count": 0, "analyzed_count": 0, "total_amount": "0", "vat_total": "0"},
         "category_totals": {}, "payment_method_totals": {},
         "members": [], "merchants": [], "previous": null, "trend": []}
        """
        let report = try decode(older)
        XCTAssertNil(report.totals.manualCount)
        XCTAssertTrue(report.isEmpty)
    }
}

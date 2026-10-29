import XCTest
@testable import Fislik

final class FormattingTests: XCTestCase {
    func testMoney() {
        XCTAssertEqual(TR.money(Decimal(string: "1482.35")), "₺1.482,35")
        XCTAssertEqual(TR.money(Decimal(string: "236.7")), "₺236,70")
        XCTAssertEqual(TR.money(nil), "—")
        XCTAssertEqual(TR.moneyWhole(Decimal(string: "6345.25")!), "₺6.345")
    }

    func testParseMoney() {
        XCTAssertEqual(TR.parseMoney("1.482,35"), Decimal(string: "1482.35"))
        XCTAssertEqual(TR.parseMoney("₺899,90"), Decimal(string: "899.9"))
        XCTAssertEqual(TR.parseMoney("12.5"), Decimal(string: "12.5"))
        XCTAssertNil(TR.parseMoney(""))
    }

    func testPeriodMath() {
        let p = Period("2026-10")!
        XCTAssertEqual(p.title, "Ekim 2026")
        XCTAssertEqual(p.upperTitle, "EKİM 2026")
        XCTAssertEqual(p.next.raw, "2026-11")
        XCTAssertEqual(Period("2026-01")!.previous.raw, "2025-12")
        XCTAssertEqual(Period("2026-12")!.next.raw, "2027-01")
        XCTAssertNil(Period("2026-13"))
        XCTAssertEqual(p.renewalLabel, "1 Kasım")
    }

    func testDates() {
        let d = DateParsing.parse("2026-10-24")!
        XCTAssertEqual(DateParsing.dayString(d), "2026-10-24")
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00.123456+00:00"))
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00.123456"))
    }

    func testStrings() {
        XCTAssertEqual("Ayşe Yıldırım".initials, "AY")
        XCTAssertEqual("Elif Şahin".initials, "EŞ")
        XCTAssertEqual("Ayşe Yıldırım".slug, "ayse-yildirim")
        XCTAssertTrue("a@b.co".isValidEmail)
        XCTAssertFalse("ab.co".isValidEmail)
    }
}

final class DecodingTests: XCTestCase {
    func testReceiptDecodesStringDecimals() throws {
        let json = """
        {"id":"abc","period":"2026-10","created_at":"2026-10-22T14:03:00.000001Z","image_url":"https://x/y.jpg",
         "content_type":"image/jpeg","processed":false,"open_issue":null,"uploaded_by":null,
         "extraction":{"status":"done","merchant_name":"Trendyol","merchant_legal_name":null,"receipt_date":"2026-10-22",
          "total_amount":"899.90","vat_total":"149.98","vat_breakdown":[{"rate":20,"amount":"149.98"}],"doc_type":"fatura",
          "merchant_tax_id":null,"merchant_tax_id_type":null,"merchant_tax_office":null,"receipt_number":"123",
          "payment_method":"kredi_karti","expense_category":"ofis","edited":false}}
        """
        let r = try APIClient.decoder.decode(Receipt.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertEqual(r.extraction?.totalAmount, Decimal(string: "899.90"))
        XCTAssertEqual(r.extraction?.vatBreakdown.first?.amount, Decimal(string: "149.98"))
        XCTAssertEqual(r.extraction?.receiptNumber, "123")
        XCTAssertEqual(r.extraction?.paymentMethod, .krediKarti)
    }

    func testSummaryMaps() throws {
        let json = #"{"receipt_count":8,"analyzed_count":8,"total_amount":"6345.25","vat_total":"971.85","vat_by_rate":{"20":"821.27","10":"150.58"},"payment_method_totals":{},"category_totals":{"market":"10.00"}}"#
        let s = try APIClient.decoder.decode(MonthSummary.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertEqual(s.vatByRate["20"], Decimal(string: "821.27"))
        XCTAssertEqual(s.categoryTotals["market"], 10)
    }

    func testErrorDetail() {
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":"Bu ay zaten gönderildi"}"#.utf8)), "Bu ay zaten gönderildi")
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":[{"msg":"bad"}]}"#.utf8)), "bad")
        XCTAssertEqual(APIClient.detail(from: Data(#"{"error":"Rate limit"}"#.utf8)), "Rate limit")
        XCTAssertEqual(APIError.server(status: 409, detail: "Bu ay zaten gönderildi").message, "Bu ay zaten gönderildi")
        XCTAssertEqual(APIError.server(status: 404, detail: "Receipt not found").message, "Kayıt bulunamadı.")
    }

    func testPatchEncodingOmitsAndClears() throws {
        var patch = ExtractionPatch()
        patch.merchantName = .some("Migros")
        patch.merchantTaxId = .some(nil)
        let data = try APIClient.encoder.encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["merchant_name"] as? String, "Migros")
        XCTAssertTrue(obj["merchant_tax_id"] is NSNull)
        XCTAssertNil(obj["vat_total"])
    }
}

@MainActor
final class DeepLinkTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/davet/abc")!), .invite(token: "abc"))
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/sifre-sifirla/t1")!), .passwordReset(token: "t1"))
        XCTAssertEqual(AppModel.parse(URL(string: "fislik://kamera")!), .camera)
        XCTAssertEqual(AppModel.parse(URL(string: "fislik://fis/r1?period=2026-10")!), .receipt(id: "r1", period: Period("2026-10")))
    }
}

final class QueryTests: XCTestCase {
    private func receipt(_ merchant: String, total: String, processed: Bool = false, category: ExpenseCategory = .market) -> Receipt {
        Receipt(id: UUID().uuidString, period: "2026-10", createdAt: Date(), imageUrl: nil, contentType: "image/jpeg", processed: processed, openIssue: nil,
                extraction: Extraction(status: .done, merchantName: merchant, receiptDate: DateParsing.parse("2026-10-20"), totalAmount: Decimal(string: total), vatTotal: 0, vatBreakdown: [], docType: .fis, expenseCategory: category, edited: false),
                uploadedBy: nil)
    }

    func testTextAndFilters() {
        let p = Period("2026-10")!
        var q = ReceiptQuery()
        q.text = "mig"
        XCTAssertTrue(q.matches(receipt("Migros", total: "10"), period: p, now: p))
        XCTAssertFalse(q.matches(receipt("Shell", total: "10"), period: p, now: p))
        q.text = ""
        q.status = .processed
        XCTAssertFalse(q.matches(receipt("Migros", total: "10"), period: p, now: p))
        q.status = .all
        q.minAmount = "100"
        XCTAssertFalse(q.matches(receipt("Migros", total: "99,99"), period: p, now: p))
        q.minAmount = ""
        q.range = .thisMonth
        XCTAssertFalse(q.matches(receipt("Migros", total: "1"), period: p.previous, now: p))
    }

    func testDuplicatesAndWrongMonth() {
        let a = receipt("Getir", total: "164.50"), b = receipt("Getir", total: "164.50"), c = receipt("Getir", total: "1")
        XCTAssertEqual([a, b, c].duplicateIds, [a.id, b.id])
        var moved = a
        moved.period = "2026-11"
        XCTAssertTrue(moved.isWrongMonth)
        XCTAssertEqual(moved.wrongMonthTarget, Period("2026-10"))
    }
}

final class DisplayCaseTests: XCTestCase {
    func testDisplayCased() {
        XCTAssertEqual("ABDULLAH AKLAN UNLU MAMÜLLER".displayCased, "Abdullah Aklan Unlu Mamüller")
        XCTAssertEqual("KASAP HASAN".displayCased, "Kasap Hasan")
        XCTAssertEqual("İSTANBUL ŞUBESİ".displayCased, "İstanbul Şubesi")
        XCTAssertEqual("A101".displayCased, "A101")
        XCTAssertEqual("BİM".displayCased, "BİM")
        XCTAssertEqual("Türk Telekom".displayCased, "Türk Telekom")
        XCTAssertEqual("SHELL TURCAS".displayCased, "Shell Turcas")
    }
}

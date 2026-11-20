import XCTest
@testable import Fislik

final class SubscriptionTests: XCTestCase {
    func testDecodesDetectedSubscriptions() throws {
        let json = """
        {"available": true, "yearly_total": "11306.88", "dismissed_count": 1, "items": [
          {"id": "s1", "name": "Türk Telekom", "category": "iletisim", "last_amount": "849.00", "monthly_average": "712.25",
           "yearly_estimate": "8547.00", "months_seen": 6, "last_date": "2026-11-12", "day_of_month": 12,
           "price_change_percent": 32, "price_increased": true},
          {"id": "s2", "name": "Netflix", "category": "abonelik", "last_amount": "229.99", "monthly_average": "229.99",
           "yearly_estimate": "2759.88", "months_seen": 4, "last_date": "2026-11-05", "day_of_month": 5,
           "price_change_percent": null, "price_increased": false}]}
        """
        let data = try APIClient.decoder.decode(DetectedSubscriptions.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertTrue(data.available)
        XCTAssertEqual(data.yearlyTotal, Decimal(string: "11306.88"))
        XCTAssertEqual(data.items[0].lastAmount, 849)
        XCTAssertEqual(data.items[0].priceChangePercent, 32)
        XCTAssertNil(data.items[1].priceChangePercent)
        XCTAssertEqual(data.items[1].line, "Her ay ~₺229,99 · 4 aydır · son ödeme 5 Kasım 2026")
    }
}

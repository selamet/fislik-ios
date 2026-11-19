import XCTest
@testable import Fislik

final class StatementTests: XCTestCase {
    private let json = """
    {"id": "s1", "file_name": "ekim.pdf", "status": "done", "error": null, "created_at": "2026-11-01T09:00:00Z",
     "line_count": 4, "missing_count": 2, "first_date": "2026-10-03", "last_date": "2026-10-22",
     "lines": [
       {"id": "l1", "line_date": "2026-10-03", "description": "SHELL", "amount": "1200.00", "state": "matched",
        "match": {"kind": "receipt", "id": "r1", "label": "Shell", "date": "2026-10-01"}},
       {"id": "l2", "line_date": "2026-10-20", "description": "NETFLIX", "amount": "229.99", "state": "missing", "match": null},
       {"id": "l3", "line_date": "2026-10-07", "description": "MIGROS", "amount": "320.40", "state": "missing", "match": null},
       {"id": "l4", "line_date": "2026-10-22", "description": "ATM", "amount": "500.00", "state": "ignored", "match": null}]}
    """

    private func decode() throws -> Statement {
        try APIClient.decoder.decode(Statement.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
    }

    func testDecodesAStatementAndSortsMissingLinesFirst() throws {
        let statement = try decode()
        XCTAssertEqual(statement.sortedLines.map(\.id), ["l3", "l2", "l1", "l4"])
        XCTAssertEqual(statement.lines?[1].amount, Decimal(string: "229.99"))
        XCTAssertEqual(statement.lines?[0].matchLabel, "Fiş: Shell · 1 Ekim 2026")
        XCTAssertNil(statement.lines?[1].matchLabel)
        XCTAssertEqual(statement.lines?[3].stateLabel, "Yok sayıldı")
    }

    func testSummaries() throws {
        let statement = try decode()
        XCTAssertEqual(statement.summary, "3 Ekim 2026 – 22 Ekim 2026 · 4 harcama · 2 harcamanın fişi eksik")
        let failed = try APIClient.decoder.decode(Statement.self, from: Data("""
        {"id": "s2", "file_name": "x.pdf", "status": "failed", "error": "Ekstre okunamadı.", "created_at": "2026-11-01T09:00:00Z",
         "line_count": 0, "missing_count": 0, "first_date": null, "last_date": null}
        """.utf8))
        XCTAssertEqual(failed.summary, "Ekstre okunamadı.")
        XCTAssertNil(failed.lines)
    }

    func testErrorMessages() {
        XCTAssertEqual(StatementFiles.message(for: .server(status: 402, detail: "paid_plan_required")), "Ekstre yükleme Pro ve İşletme planlarında.")
        XCTAssertTrue(StatementFiles.message(for: .server(status: 402, detail: "not_enough_credits")).contains("5 hak"))
        XCTAssertEqual(StatementFiles.message(for: .server(status: 422, detail: "Dosya geçerli bir PDF değil.")), "Dosya geçerli bir PDF değil.")
    }

    func testFileTypes() {
        XCTAssertEqual(StatementFiles.mimeType(for: "Ekstre.PDF"), "application/pdf")
        XCTAssertEqual(StatementFiles.mimeType(for: "a.xlsx"), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        XCTAssertEqual(StatementFiles.mimeType(for: "a.csv"), "text/csv")
        XCTAssertEqual(StatementFiles.allowedTypes.count, 3)
    }

    func testMultipartBody() {
        let body = APIClient.multipartBody(boundary: "B", field: "file", fileName: "ek\"im\n.pdf", mimeType: "application/pdf", data: Data("%PDF".utf8))
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ek'im.pdf\"\r\nContent-Type: application/pdf\r\n\r\n%PDF\r\n--B--\r\n")
    }
}

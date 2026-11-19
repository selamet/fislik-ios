import Foundation
import UniformTypeIdentifiers

/// What a statement line was paired with.
struct StatementMatch: Codable, Equatable {
    let kind: String
    let id: String
    let label: String?
    let date: String?
}

struct StatementLine: Codable, Equatable, Identifiable {
    enum State: String, Codable { case matched, missing, expensed, ignored }

    let id: String
    let lineDate: String
    let description: String
    let amount: Decimal
    let state: State
    let match: StatementMatch?

    var stateLabel: String {
        switch state {
        case .matched: "Eşleşti"
        case .missing: "Fişi eksik"
        case .expensed: "Gider olarak eklendi"
        case .ignored: "Yok sayıldı"
        }
    }

    /// "Fiş: Shell · 1 Ekim 2026"
    var matchLabel: String? {
        guard let match else { return nil }
        let kind = match.kind == "receipt" ? "Fiş" : "Gider"
        let name = match.label ?? (match.kind == "receipt" ? "satıcısı okunamadı" : "")
        let date = match.date.map { " · \(ExpenseDay.label($0))" } ?? ""
        return "\(kind): \(name)\(date)"
    }
}

/// A card or bank statement uploaded to find spending without a receipt.
struct Statement: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case processing, done, failed }

    let id: String
    let fileName: String
    let status: Status
    let error: String?
    let createdAt: Date
    let lineCount: Int
    /// Lines still waiting for a receipt or a decision.
    let missingCount: Int
    let firstDate: String?
    let lastDate: String?
    /// Only in the detail reply.
    var lines: [StatementLine]?

    var dateRange: String? {
        guard let firstDate, let lastDate else { return nil }
        return firstDate == lastDate ? ExpenseDay.label(firstDate) : "\(ExpenseDay.label(firstDate)) – \(ExpenseDay.label(lastDate))"
    }

    /// One line under the file name in the list.
    var summary: String {
        switch status {
        case .processing: return "Okunuyor…"
        case .failed: return error ?? "Okunamadı"
        case .done:
            let missing = missingCount == 0 ? "eksik fiş yok" : "\(missingCount) harcamanın fişi eksik"
            return [dateRange, "\(lineCount) harcama", missing].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Missing lines first (they need a decision), each group by date.
    var sortedLines: [StatementLine] {
        let order: [StatementLine.State: Int] = [.missing: 0, .matched: 1, .expensed: 2, .ignored: 3]
        return (lines ?? []).sorted { (order[$0.state]!, $0.lineDate) < (order[$1.state]!, $1.lineDate) }
    }
}

struct LineExpenseBody: Encodable {
    let category: String
    let description: String?
}

struct LineIgnoreBody: Encodable { let ignored: Bool }

enum StatementFiles {
    /// Credits a statement uses; mirrors the API.
    static let credits = 5
    static let maxBytes = 10 * 1024 * 1024

    static var allowedTypes: [UTType] {
        [.pdf, .commaSeparatedText, UTType(filenameExtension: "xlsx")].compactMap { $0 }
    }

    static func mimeType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": "text/csv"
        default: "application/octet-stream"
        }
    }

    /// Turkish message for a refused statement request: the API explains
    /// unreadable files itself; plan and credit refusals get their own copy.
    static func message(for error: APIError) -> String {
        if case .server(let status, let detail) = error {
            if status == 402 {
                return detail == "not_enough_credits"
                    ? "Bu ayki limitinde yeterli hak kalmadı; bir ekstre \(credits) hak kullanır."
                    : "Ekstre yükleme Pro ve İşletme planlarında."
            }
            if status == 422 || status == 409, let detail { return detail }
        }
        return error.message
    }
}

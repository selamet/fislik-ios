import Foundation

/// Counts and amounts of a set of receipts.
struct ReportTotals: Codable, Equatable {
    var receiptCount: Int
    var analyzedCount: Int
    /// Receipts and manual expenses together.
    var totalAmount: Decimal
    var vatTotal: Decimal
    /// The part entered by hand (no receipt); absent on older APIs.
    var manualCount: Int?
    var manualAmount: Decimal?

    var hasManual: Bool { (manualCount ?? 0) > 0 }

    /// Receipts uploaded but not read yet; their amounts are not in the totals.
    var waitingCount: Int { max(receiptCount - analyzedCount, 0) }
}

struct ReportPeriodTotals: Codable, Equatable, Identifiable {
    var period: String
    var receiptCount: Int
    var analyzedCount: Int
    var totalAmount: Decimal
    var vatTotal: Decimal

    var id: String { period }
    /// "Eki" — the label under a trend bar.
    var shortMonth: String { Period(period).map { TR.shortMonths[$0.month - 1] } ?? period }
    var title: String { Period(period)?.title ?? period }
}

struct ReportMember: Codable, Equatable, Identifiable {
    /// Nil when the uploader's account no longer exists.
    var userId: String?
    var name: String
    /// "member" or "accountant" (a granted accountant who uploaded for the company).
    var kind: String
    var receiptCount: Int
    var totalAmount: Decimal
    var vatTotal: Decimal

    var id: String { userId ?? name }
    var isAccountant: Bool { kind == "accountant" }
}

struct ReportMerchant: Codable, Equatable, Identifiable {
    /// Nil groups the receipts whose merchant could not be read.
    var name: String?
    var receiptCount: Int
    var totalAmount: Decimal

    var id: String { name ?? "-" }
    var label: String { name ?? "Satıcısı okunamayan fişler" }
}

/// Spending report of the active company for one month (`GET /reports/monthly`).
struct MonthlyReport: Codable, Equatable {
    var period: String
    /// "company": every receipt of the company; "own": only the caller's.
    var scope: String
    /// Whether the plan includes members, merchants, previous and trend.
    var detailed: Bool
    var totals: ReportTotals
    var categoryTotals: [String: Decimal]
    var paymentMethodTotals: [String: Decimal]
    var members: [ReportMember]
    var merchants: [ReportMerchant]
    var previous: ReportPeriodTotals?
    var trend: [ReportPeriodTotals]

    var isOwnScope: Bool { scope == "own" }
    /// Empty only when the month has neither receipts nor manual expenses.
    var isEmpty: Bool { totals.receiptCount == 0 && !totals.hasManual }

    /// Categories, largest first, with their Turkish labels.
    var categories: [ReportLine] {
        Self.lines(categoryTotals) { CategoryLabels.label($0) }
    }

    /// Payment methods, largest first, with their Turkish labels.
    var paymentMethods: [ReportLine] {
        Self.lines(paymentMethodTotals) { PaymentMethod(rawValue: $0)?.label ?? $0 }
    }

    /// Signed whole-percent change against the previous month; nil when
    /// there is no previous month or it had no spending.
    var changePercent: Int? {
        guard let previous, previous.totalAmount > 0 else { return nil }
        let ratio = (totals.totalAmount - previous.totalAmount) / previous.totalAmount * 100
        return Int((ratio as NSDecimalNumber).doubleValue.rounded())
    }

    private static func lines(_ totals: [String: Decimal], label: (String) -> String) -> [ReportLine] {
        totals
            .map { ReportLine(key: $0.key, label: label($0.key), amount: $0.value) }
            .sorted { ($0.amount, $1.label) > ($1.amount, $0.label) }
    }
}

/// One labelled amount of a breakdown.
struct ReportLine: Equatable, Identifiable {
    let key: String
    let label: String
    let amount: Decimal

    var id: String { key }
}

enum ReportMath {
    /// A part of a total as a 0...1 fraction; 0 when there is nothing to share.
    static func share(_ amount: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        let ratio = ((amount / total) as NSDecimalNumber).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// "%42" — Turkish puts the percent sign first.
    static func percent(_ fraction: Double) -> String { "%\(Int((fraction * 100).rounded()))" }

    /// "+%39" / "−%12" / "%0".
    static func signedPercent(_ value: Int) -> String {
        (value > 0 ? "+" : value < 0 ? "−" : "") + "%\(abs(value))"
    }

    /// Bar heights (0...1) of a trend, relative to its largest month.
    static func heights(_ trend: [ReportPeriodTotals]) -> [Double] {
        let largest = trend.map(\.totalAmount).max() ?? 0
        return trend.map { share($0.totalAmount, of: largest) }
    }
}

/// Labels of every category a report or a manual expense can carry: the
/// receipt categories plus the ones that only exist for manual entries.
enum CategoryLabels {
    static let manual: [(key: String, label: String)] = [
        ("kira", "Kira"),
        ("maas", "Maaş ve personel"),
        ("abonelik", "Abonelik ve yazılım"),
        ("banka", "Banka ve finansman"),
        ("vergi", "Vergi ve resmi ödemeler"),
        ("fatura", "Fatura (elektrik, su, doğalgaz)"),
    ]

    /// Every category in the order a picker shows them: manual-only first.
    static let all: [(key: String, label: String)] =
        manual + ExpenseCategory.allCases.map { ($0.rawValue, $0.label) }

    static func label(_ key: String) -> String {
        all.first { $0.key == key }?.label ?? key
    }
}

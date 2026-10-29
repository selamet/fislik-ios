import SwiftUI

enum ReceiptFilter: Hashable, CaseIterable {
    case all, unprocessed, processed, issues
}

/// Derived, display-ready facts about a receipt.
extension Receipt {
    var merchant: String {
        if let name = extraction?.merchantName?.nilIfBlank { return name }
        switch extraction?.status {
        case .pending?: return "Analiz ediliyor…"
        case .failed?: return "Okunamadı"
        default: return extraction == nil ? "Sıraya alındı" : "Bilinmeyen satıcı"
        }
    }

    var total: Decimal? { extraction?.totalAmount }
    var vat: Decimal? { extraction?.vatTotal }
    var isFatura: Bool { extraction?.docType == .fatura }
    var isPending: Bool { extraction?.status == .pending }
    var isQueued: Bool { extraction == nil }
    var isFailed: Bool { extraction?.status == .failed }
    var uploadedByAccountant: Bool { uploadedBy != nil }

    /// Receipt date when known, otherwise upload time.
    var displayDate: Date { extraction?.receiptDate ?? createdAt }

    var categoryLabel: String? { extraction?.expenseCategory?.label }

    /// The receipt date belongs to another month than the one it was filed under.
    var isWrongMonth: Bool {
        guard let date = extraction?.receiptDate, let p = Period(period) else { return false }
        return !p.contains(date)
    }

    var wrongMonthTarget: Period? {
        guard isWrongMonth, let date = extraction?.receiptDate else { return nil }
        return Period(date: date)
    }

    func matches(_ filter: ReceiptFilter) -> Bool {
        switch filter {
        case .all: true
        case .unprocessed: !processed
        case .processed: processed
        case .issues: openIssue != nil
        }
    }

    /// Primary status shown in rows ("● İşlendi").
    var status: (label: String, color: Color) {
        if processed { return ("İşlendi", FColor.success) }
        if openIssue != nil { return ("Sorun var", FColor.warning) }
        if isQueued { return ("Sıraya alındı", FColor.muted) }
        if isPending { return ("Analiz ediliyor", FColor.brand) }
        if isFailed { return ("Okunamadı", FColor.warning) }
        return ("İşlenmedi", FColor.muted)
    }

    /// Stacked badges on the grid card (top-right).
    func badges(duplicate: Bool) -> [(String, Color)] {
        var out: [(String, Color)] = []
        if processed { out.append(("İşlendi", FColor.success)) }
        if openIssue != nil { out.append(("Sorun var", FColor.warning)) }
        if isWrongMonth { out.append(("Farklı ay", FColor.warning)) }
        if duplicate { out.append(("Mükerrer olabilir", FColor.warning)) }
        if uploadedByAccountant { out.append(("Muhasebeci yükledi", FColor.muted)) }
        if isQueued { out.append(("Sıraya alındı", FColor.muted)) }
        return out
    }

    /// "Fatura", "Fatura · PDF", "PDF"
    var docTag: String? {
        switch (isFatura, isPDF) {
        case (true, true): "Fatura · PDF"
        case (true, false): "Fatura"
        case (false, true): "PDF"
        default: nil
        }
    }
}

extension Array where Element == Receipt {
    /// Ids of receipts that share merchant + total + date with another receipt.
    var duplicateIds: Set<String> {
        var seen: [String: String] = [:]
        var dupes = Set<String>()
        for r in self {
            guard let name = r.extraction?.merchantName?.lowercased(), let total = r.total, let date = r.extraction?.receiptDate else { continue }
            let key = "\(name)|\(total)|\(DateParsing.dayString(date))"
            if let other = seen[key] {
                dupes.insert(other)
                dupes.insert(r.id)
            } else {
                seen[key] = r.id
            }
        }
        return dupes
    }

    /// 2H grouping: this week, last week, then month halves.
    func groupedForList(period: Period, now: Date = Date()) -> [(title: String, receipts: [Receipt])] {
        let cal = Calendar.fislik
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        var buckets: [(String, [Receipt])] = []
        func add(_ title: String, _ r: Receipt) {
            if let i = buckets.firstIndex(where: { $0.0 == title }) { buckets[i].1.append(r) } else { buckets.append((title, [r])) }
        }
        let monthUpper = TR.upper(period.monthName)
        let lastDay = cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: period.year, month: period.month))!)?.count ?? 30
        for r in sorted(by: { $0.displayDate > $1.displayDate }) {
            let d = r.displayDate
            if d >= weekStart { add("BU HAFTA", r) }
            else if d >= lastWeekStart { add("GEÇEN HAFTA", r) }
            else if cal.component(.day, from: d) <= 15 { add("1–15 \(monthUpper)", r) }
            else { add("16–\(lastDay) \(monthUpper)", r) }
        }
        return buckets.map { (title: $0.0, receipts: $0.1) }
    }
}

extension Collection where Element == Receipt {
    var totalAmount: Decimal { reduce(0) { $0 + ($1.total ?? 0) } }
}

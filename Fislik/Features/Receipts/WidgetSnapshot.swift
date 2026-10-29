import Foundation

/// Builds the widget snapshot from the current month.
enum WidgetSnapshot {
    @MainActor
    static func update(from store: ReceiptStore, period: Period) {
        guard period == .current else { return }
        let state = store.state(period)
        let receipts = state.receipts
        let rows = receipts.prefix(3).map { r in
            WidgetData.Row(id: r.id, merchant: r.merchant, day: TR.shortDay(r.displayDate), status: r.status.label,
                           tone: r.processed ? "success" : (r.openIssue != nil || r.isFailed) ? "warning" : "neutral",
                           total: TR.money(r.total))
        }
        let withIssue = receipts.filter { $0.openIssue != nil }
        let question = withIssue.first.map { r in
            WidgetData.Question(accountant: r.openIssue?.authorName ?? store.activeAccountant?.displayName ?? "Muhasebecin",
                                count: withIssue.count, receiptId: r.id, merchant: r.merchant, total: TR.money(r.total))
        }
        WidgetData(period: period.raw, count: receipts.count, unprocessed: receipts.filter { !$0.processed }.count,
                   total: state.summary.totalAmount, vat: state.summary.vatTotal, recent: Array(rows), question: question, updatedAt: Date()).save()
    }
}

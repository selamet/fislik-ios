import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Snapshot the app writes for the widgets (App Group defaults).
struct WidgetData: Codable, Equatable {
    struct Row: Codable, Equatable, Identifiable {
        var id: String
        var merchant: String
        var day: String
        var status: String
        /// "success" | "warning" | "neutral"
        var tone: String
        var total: String
    }

    struct Question: Codable, Equatable {
        var accountant: String
        var count: Int
        var receiptId: String
        var merchant: String
        var total: String
    }

    var period: String
    var count: Int
    var unprocessed: Int
    var total: Decimal
    var vat: Decimal
    var recent: [Row]
    var question: Question?
    var updatedAt: Date

    static let appGroup = "group.dev.selamet.fislik"
    private static let key = "widgetData"

    static var placeholder: WidgetData {
        WidgetData(period: Period.current.raw, count: 8, unprocessed: 4, total: Decimal(string: "6345.25")!, vat: Decimal(string: "971.85")!, recent: [
            Row(id: "1", merchant: "Migros", day: "24 Eki", status: "İşlendi", tone: "success", total: "₺1.482,35"),
            Row(id: "2", merchant: "Shell", day: "23 Eki", status: "İşlendi", tone: "success", total: "₺2.350,00"),
            Row(id: "3", merchant: "Trendyol", day: "22 Eki", status: "Sorun var", tone: "warning", total: "₺899,90"),
        ], question: Question(accountant: "Zeynep Kaya", count: 1, receiptId: "3", merchant: "Trendyol", total: "₺899,90"), updatedAt: Date())
    }

    static func load() -> WidgetData? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self), data != UserDefaults(suiteName: Self.appGroup)?.data(forKey: Self.key) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    var periodValue: Period { Period(period) ?? .current }
}

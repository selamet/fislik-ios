import Foundation

/// A monthly charge the detector found (`GET /reports/subscriptions`).
struct DetectedSubscription: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let category: String
    let lastAmount: Decimal
    let monthlyAverage: Decimal
    let yearlyEstimate: Decimal
    let monthsSeen: Int
    let lastDate: String
    let dayOfMonth: Int
    let priceChangePercent: Int?
    let priceIncreased: Bool

    /// "Her ay ~₺229,99 · 4 aydır · son ödeme 5 Kasım 2026"
    var line: String {
        "Her ay ~\(TR.money(monthlyAverage)) · \(monthsSeen) aydır · son ödeme \(ExpenseDay.label(lastDate))"
    }
}

struct DetectedSubscriptions: Codable, Equatable {
    /// False on the free plan.
    let available: Bool
    let items: [DetectedSubscription]
    let yearlyTotal: Decimal
    let dismissedCount: Int
}

struct TrackSubscriptionBody: Encodable {}
struct TrackSubscriptionReply: Decodable { let recurringId: String }

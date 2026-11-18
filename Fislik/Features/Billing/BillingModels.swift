import Foundation

/// One plan of the catalog (`GET /plans`). Prices are integer kuruş.
struct Plan: Codable, Equatable, Identifiable {
    let code: String
    let name: String
    let monthlyReceipts: Int
    let webMonthlyKurus: Int
    let webYearlyKurus: Int?
    let appStoreMonthlyKurus: Int
    /// StoreKit product id of the monthly App Store subscription; nil for the free plan.
    let appStoreProductId: String?

    var id: String { code }
    var isPaid: Bool { appStoreMonthlyKurus > 0 }
}

struct CompanySubscription: Codable, Equatable {
    enum Channel: String { case iyzico, appStore = "app_store", manual }

    let plan: String
    let channel: String
    let interval: String
    let status: String
    /// Renewal date, or the day the plan ends when `cancelAtPeriodEnd`.
    let currentPeriodEnd: Date?
    let cancelAtPeriodEnd: Bool

    var source: Channel? { Channel(rawValue: channel) }
    var isActive: Bool { status == "active" }
    var isPastDue: Bool { status == "past_due" }
}

/// Billing state of the active company (`GET /billing/me`).
struct Billing: Codable, Equatable {
    /// The plan in effect right now; free without an entitled subscription.
    let plan: Plan
    /// Can be present while `plan` is free (payment past due).
    let subscription: CompanySubscription?
    let usage: Credits
    let customLimit: Bool
    /// Whether the signed-in member may buy or change the plan.
    let canManage: Bool
}

enum BillingFormat {
    /// Integer kuruş → "229 TL" / "2.189 TL" / "229,50 TL". Used when the App
    /// Store has no localized price to show.
    static func kurus(_ kurus: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let lira = formatter.string(from: NSNumber(value: kurus / 100)) ?? "\(kurus / 100)"
        let rest = abs(kurus % 100)
        return rest == 0 ? "\(lira) TL" : "\(lira),\(String(format: "%02d", rest)) TL"
    }
}

/// What the plan screen offers for one plan card.
enum PlanAction: Equatable {
    /// Nothing to do: the free plan, or the member cannot manage billing.
    case none
    case current
    /// Buy, or move to it within the App Store subscription group.
    case buy
    /// The App Store has not returned this product.
    case unavailable
    /// The company's subscription is managed elsewhere.
    case managedOnWeb
    case managedBySupport
}

extension Billing {
    /// The action for `plan`. `hasProduct` tells whether StoreKit returned the product.
    func action(for plan: Plan, hasProduct: Bool) -> PlanAction {
        if plan.code == self.plan.code { return .current }
        guard plan.isPaid, canManage else { return .none }
        if let subscription {
            switch subscription.source {
            case .iyzico: return .managedOnWeb
            case .manual: return .managedBySupport
            case .appStore, .none: break
            }
        }
        return hasProduct ? .buy : .unavailable
    }
}

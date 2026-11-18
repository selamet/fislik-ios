import Foundation

/// The API calls the billing store needs, injectable for tests.
struct BillingAPI: Sendable {
    var plans: @Sendable () async throws -> [Plan]
    var billing: @Sendable () async throws -> Billing
    var attach: @Sendable (_ signedTransaction: String) async throws -> CompanySubscription

    static let live = BillingAPI(
        plans: { try await API.plans() },
        billing: { try await API.billing() },
        attach: { try await API.attachAppStoreTransaction($0) }
    )
}

/// A one-line outcome shown on the plan screen.
struct BillingNotice: Equatable {
    enum Tone: Equatable { case success, info, error }
    let tone: Tone
    let text: String
}

/// Plan, usage and App Store purchases for the active company.
@MainActor
@Observable
final class BillingStore {
    static let shared = BillingStore()

    private(set) var billing: Billing?
    private(set) var plans: [Plan] = []
    /// Product id → localized App Store price.
    private(set) var prices: [String: String] = [:]
    private(set) var loaded = false
    /// Plan code being bought right now.
    private(set) var purchasing: String?
    private(set) var restoring = false
    var notice: BillingNotice?
    var error: APIError?

    private let storefront: PurchaseGateway
    private let api: BillingAPI
    private var listener: Task<Void, Never>?

    init(storefront: PurchaseGateway = AppStoreGateway(), api: BillingAPI = .live) {
        self.storefront = storefront
        self.api = api
    }

    var busy: Bool { purchasing != nil || restoring }

    func price(for plan: Plan) -> String {
        if !plan.isPaid { return "Ücretsiz" }
        if let id = plan.appStoreProductId, let price = prices[id] { return price }
        return BillingFormat.kurus(plan.appStoreMonthlyKurus)
    }

    func action(for plan: Plan) -> PlanAction {
        guard let billing else { return .none }
        return billing.action(for: plan, hasProduct: plan.appStoreProductId.map { prices[$0] != nil } ?? false)
    }

    func load() async {
        do {
            async let billing = api.billing()
            async let plans = api.plans()
            self.billing = try await billing
            self.plans = try await plans
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .decoding
        }
        prices = await storefront.prices(for: plans.compactMap(\.appStoreProductId))
        loaded = true
    }

    /// Only the billing state; cheap enough to call after anything that may change it.
    func refresh() async {
        if let fresh = try? await api.billing() { billing = fresh }
    }

    func purchase(_ plan: Plan) async {
        guard !busy, let productId = plan.appStoreProductId else { return }
        purchasing = plan.code
        notice = nil
        defer { purchasing = nil }
        do {
            switch try await storefront.purchase(productId: productId) {
            case .purchased(let transaction):
                try await deliver(transaction)
                await refresh()
                await ReceiptStore.shared.refreshCredits()
                notice = BillingNotice(tone: .success, text: "\(plan.name) planı etkin. Limit nedeniyle bekleyen fişler birkaç dakika içinde okunur.")
            case .pending:
                notice = BillingNotice(tone: .info, text: "Satın alma onay bekliyor. Onaylandığında plan kendiliğinden etkinleşir.")
            case .cancelled:
                break
            }
        } catch {
            notice = BillingNotice(tone: .error, text: Self.message(for: error))
        }
    }

    func restore() async {
        guard !busy else { return }
        restoring = true
        notice = nil
        defer { restoring = false }
        do {
            try await storefront.sync()
        } catch {
            notice = BillingNotice(tone: .error, text: "App Store'a ulaşılamadı. Biraz sonra tekrar dene.")
            return
        }
        let transactions = await storefront.entitlements()
        guard !transactions.isEmpty else {
            notice = BillingNotice(tone: .info, text: "Bu Apple hesabında geri yüklenecek bir abonelik bulunamadı.")
            return
        }
        var restored = false
        var failure: Error?
        for transaction in transactions {
            do {
                try await deliver(transaction)
                restored = true
            } catch {
                failure = error
            }
        }
        await refresh()
        await ReceiptStore.shared.refreshCredits()
        if restored {
            notice = BillingNotice(tone: .success, text: "Aboneliğin geri yüklendi.")
        } else if let failure {
            notice = BillingNotice(tone: .error, text: Self.message(for: failure))
        }
    }

    /// Delivers transactions the API has not seen: unfinished ones from an
    /// earlier launch and anything that completes outside the purchase flow
    /// (approved Ask to Buy, a purchase from the App Store page).
    func startListening() {
        guard listener == nil else { return }
        listener = Task { [weak self, storefront] in
            for await transaction in storefront.updates() {
                guard let self else { return }
                if (try? await self.deliver(transaction)) != nil {
                    await self.refresh()
                }
            }
        }
    }

    func reset() {
        listener?.cancel()
        listener = nil
        billing = nil
        plans = []
        prices = [:]
        loaded = false
        notice = nil
        error = nil
    }

    /// Hands a transaction to the API and finishes it once the API has given
    /// a final answer. A transport failure leaves it unfinished, so StoreKit
    /// offers it again and nothing the user paid for is lost.
    private func deliver(_ transaction: SignedTransaction) async throws {
        do {
            _ = try await api.attach(transaction.jws)
            await transaction.finish()
        } catch let apiError as APIError {
            if let status = apiError.status, (400..<500).contains(status), status != 401 {
                await transaction.finish()
            }
            throw apiError
        }
    }

    static func message(for error: Error) -> String {
        if let storefrontError = error as? PurchaseError {
            switch storefrontError {
            case .productUnavailable: return "Bu plan şu an App Store'da satın alınamıyor."
            case .unverified: return "Satın alma doğrulanamadı. Tekrar dene."
            }
        }
        if let apiError = error as? APIError {
            switch apiError.detail {
            case "subscription_exists":
                return "Şirketin başka bir kanaldan alınmış aboneliği var. Bu satın alma şirkete tanımlanmadı; App Store aboneliğini Ayarlar > Abonelikler bölümünden iptal edebilirsin."
            case "transaction_belongs_to_another_company":
                return "Bu Apple hesabındaki abonelik başka bir şirkete tanımlı."
            case "transaction_not_active":
                return "Aktif bir abonelik bulunamadı."
            case "invalid_transaction":
                return "Satın alma doğrulanamadı."
            default:
                if apiError.status == 403 { return "Planı yalnızca şirket sahibi ya da yöneticisi değiştirebilir." }
                return apiError.message
            }
        }
        return "Satın alma tamamlanamadı. Tekrar dene."
    }
}

import XCTest
@testable import Fislik

private func plan(_ code: String, kurus: Int = 0, product: String? = nil, receipts: Int = 10) -> Plan {
    Plan(code: code, name: code == "free" ? "Ücretsiz" : code == "pro" ? "Pro" : "İşletme", monthlyReceipts: receipts,
         webMonthlyKurus: 0, webYearlyKurus: nil, appStoreMonthlyKurus: kurus, appStoreProductId: product)
}

private let free = plan("free")
private let pro = plan("pro", kurus: 22900, product: "pro.monthly", receipts: 200)
private let business = plan("business", kurus: 82900, product: "business.monthly", receipts: 1000)

private func billing(_ current: Plan = free, subscription: CompanySubscription? = nil, canManage: Bool = true) -> Billing {
    Billing(plan: current, subscription: subscription,
            usage: Credits(limit: current.monthlyReceipts, used: 4, remaining: current.monthlyReceipts - 4, unlimited: false),
            customLimit: false, canManage: canManage)
}

private func subscription(_ plan: String = "pro", channel: String = "app_store", status: String = "active",
                          end: Date? = Date(timeIntervalSince1970: 1_797_588_000), cancel: Bool = false) -> CompanySubscription {
    CompanySubscription(plan: plan, channel: channel, interval: "monthly", status: status, currentPeriodEnd: end, cancelAtPeriodEnd: cancel)
}

/// Scripted App Store.
private final class FakeGateway: PurchaseGateway, @unchecked Sendable {
    var priceList: [String: String] = ["pro.monthly": "₺229,00", "business.monthly": "₺829,00"]
    var purchaseResult: Result<StorePurchaseResult, Error> = .success(.cancelled)
    var owned: [SignedTransaction] = []
    var syncError: Error?
    private(set) var purchased: [String] = []
    private(set) var finished: [String] = []
    private var continuation: AsyncStream<SignedTransaction>.Continuation?

    func transaction(_ jws: String) -> SignedTransaction {
        SignedTransaction(jws: jws) { [weak self] in self?.finished.append(jws) }
    }

    func prices(for productIds: [String]) async -> [String: String] { priceList.filter { productIds.contains($0.key) } }
    func purchase(productId: String) async throws -> StorePurchaseResult {
        purchased.append(productId)
        return try purchaseResult.get()
    }
    func entitlements() async -> [SignedTransaction] { owned }
    func sync() async throws { if let syncError { throw syncError } }
    func updates() -> AsyncStream<SignedTransaction> {
        AsyncStream { self.continuation = $0 }
    }
    func emit(_ transaction: SignedTransaction) { continuation?.yield(transaction) }
}

/// Scripted API.
private final class FakeBillingAPI: @unchecked Sendable {
    var current = billing()
    var attachError: APIError?
    private(set) var attached: [String] = []

    var api: BillingAPI {
        BillingAPI(
            plans: { [free, pro, business] },
            billing: { self.current },
            attach: { jws in
                if let error = self.attachError { throw error }
                self.attached.append(jws)
                self.current = billing(pro, subscription: subscription())
                return subscription()
            }
        )
    }
}

final class BillingModelTests: XCTestCase {
    func testDecodesBillingFromTheAPI() throws {
        let json = """
        {"plan": {"code": "pro", "name": "Pro", "monthly_receipts": 200, "currency": "TRY", "web_monthly_kurus": 19900,
                  "web_yearly_kurus": 218900, "app_store_monthly_kurus": 22900, "app_store_product_id": "dev.selamet.fislik.pro.monthly"},
         "subscription": {"plan": "pro", "channel": "app_store", "interval": "monthly", "status": "active",
                          "current_period_end": "2026-12-18T10:00:00Z", "cancel_at_period_end": false},
         "usage": {"limit": 200, "used": 40, "remaining": 160, "unlimited": false},
         "custom_limit": false, "can_manage": true}
        """
        let decoded = try APIClient.decoder.decode(Billing.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.plan.appStoreProductId, "dev.selamet.fislik.pro.monthly")
        XCTAssertEqual(decoded.plan.appStoreMonthlyKurus, 22900)
        XCTAssertEqual(decoded.subscription?.source, .appStore)
        XCTAssertNotNil(decoded.subscription?.currentPeriodEnd)
        XCTAssertEqual(decoded.usage.remaining, 160)
        XCTAssertTrue(decoded.canManage)
    }

    func testDecodesTheFreePlanWithoutAProduct() throws {
        let json = """
        [{"code": "free", "name": "Ücretsiz", "monthly_receipts": 10, "currency": "TRY", "web_monthly_kurus": 0,
          "web_yearly_kurus": null, "app_store_monthly_kurus": 0, "app_store_product_id": null}]
        """
        let plans = try APIClient.decoder.decode([Plan].self, from: Data(json.utf8))
        XCTAssertNil(plans[0].appStoreProductId)
        XCTAssertFalse(plans[0].isPaid)
    }

    func testCancelledRequestsAreNotConnectionErrors() {
        XCTAssertTrue(APIClient.map(URLError(.cancelled)).isCancellation)
        XCTAssertFalse(APIClient.map(URLError(.timedOut)).isCancellation)
        XCTAssertFalse(APIClient.map(URLError(.notConnectedToInternet)).isCancellation)
        XCTAssertFalse(APIError.server(status: 500, detail: nil).isCancellation)
    }

    func testTeamSizeLines() {
        XCTAssertEqual(PlanFeatures.team(1), "Tek kullanıcı (yalnızca şirket sahibi)")
        XCTAssertEqual(PlanFeatures.team(3), "3 kişilik ekip")
        XCTAssertEqual(PlanFeatures.team(nil), "Sınırsız ekip üyesi")
    }

    func testTeamIsFull() throws {
        func state(_ count: Int?, _ limit: Int?) -> Billing {
            var b = billing()
            b.memberCount = count
            b.memberLimit = limit
            return b
        }
        XCTAssertTrue(state(1, 1).teamIsFull)
        XCTAssertTrue(state(4, 3).teamIsFull)
        XCTAssertFalse(state(2, 3).teamIsFull)
        XCTAssertFalse(state(40, nil).teamIsFull)
        XCTAssertFalse(state(nil, nil).teamIsFull)
        // Older API responses without the fields decode as "not full".
        let json = #"{"plan": {"code": "free", "name": "Ücretsiz", "monthly_receipts": 10, "currency": "TRY", "web_monthly_kurus": 0, "web_yearly_kurus": null, "app_store_monthly_kurus": 0, "app_store_product_id": null}, "subscription": null, "usage": {"limit": 10, "used": 1, "remaining": 9, "unlimited": false}, "custom_limit": false, "can_manage": true}"#
        XCTAssertFalse(try APIClient.decoder.decode(Billing.self, from: Data(json.utf8)).teamIsFull)
    }

    func testPlanFeatureLists() {
        for code in ["free", "pro", "business"] {
            XCTAssertFalse(PlanFeatures.features(code).isEmpty)
            XCTAssertFalse(PlanFeatures.tagline(code).isEmpty)
        }
        XCTAssertEqual(PlanFeatures.features("pro").first, "Ücretsiz plandaki her şey")
        XCTAssertEqual(PlanFeatures.features("business").first, "Pro plandaki her şey")
        XCTAssertEqual(PlanFeatures.features("unknown"), PlanFeatures.features("free"))
    }

    func testPlanSummaryFootnote() {
        let open = Credits(limit: 10, used: 4, remaining: 6, unlimited: false)
        let full = Credits(limit: 10, used: 10, remaining: 0, unlimited: false)
        let unlimited = Credits(limit: nil, used: 40, remaining: nil, unlimited: true)
        XCTAssertTrue(PlanSummaryCard.footnote(open).hasPrefix("Tüm üyeler aynı havuzu kullanır ·"))
        XCTAssertTrue(PlanSummaryCard.footnote(full).hasPrefix("Limit doldu"))
        XCTAssertEqual(PlanSummaryCard.footnote(unlimited), "Tüm üyeler aynı havuzu kullanır")
    }

    func testKurusFormatting() {
        XCTAssertEqual(BillingFormat.kurus(22900), "229 TL")
        XCTAssertEqual(BillingFormat.kurus(218900), "2.189 TL")
        XCTAssertEqual(BillingFormat.kurus(22950), "229,50 TL")
        XCTAssertEqual(BillingFormat.kurus(0), "0 TL")
    }

    func testPlanActions() {
        let onFree = billing()
        XCTAssertEqual(onFree.action(for: free, hasProduct: false), .current)
        XCTAssertEqual(onFree.action(for: pro, hasProduct: true), .buy)
        XCTAssertEqual(onFree.action(for: pro, hasProduct: false), .unavailable)

        let onPro = billing(pro, subscription: subscription())
        XCTAssertEqual(onPro.action(for: pro, hasProduct: true), .current)
        XCTAssertEqual(onPro.action(for: business, hasProduct: true), .buy)
        XCTAssertEqual(onPro.action(for: free, hasProduct: false), .none)

        XCTAssertEqual(billing(pro, subscription: subscription(channel: "iyzico")).action(for: business, hasProduct: true), .managedOnWeb)
        XCTAssertEqual(billing(pro, subscription: subscription(channel: "manual")).action(for: business, hasProduct: true), .managedBySupport)
        // A past-due web subscription still owns the company's slot.
        XCTAssertEqual(billing(free, subscription: subscription(channel: "iyzico", status: "past_due")).action(for: pro, hasProduct: true), .managedOnWeb)
        XCTAssertEqual(billing(canManage: false).action(for: pro, hasProduct: true), .none)
    }

    func testLimitState() {
        func credits(_ used: Int, _ limit: Int?) -> Credits {
            Credits(limit: limit, used: used, remaining: limit.map { max(0, $0 - used) }, unlimited: limit == nil)
        }
        XCTAssertEqual(credits(7, 10).limitState, .ok)
        XCTAssertEqual(credits(8, 10).limitState, .near)
        XCTAssertEqual(credits(10, 10).limitState, .full)
        XCTAssertEqual(credits(12, 10).limitState, .full)
        XCTAssertEqual(credits(799, 1000).limitState, .ok)
        XCTAssertEqual(credits(800, 1000).limitState, .near)
        XCTAssertEqual(credits(5000, nil).limitState, .ok)
    }

    func testManagedElsewhereBanner() {
        XCTAssertNil(PlanScreen.managedElsewhere(billing()))
        XCTAssertNil(PlanScreen.managedElsewhere(billing(pro, subscription: subscription())))
        XCTAssertTrue(PlanScreen.managedElsewhere(billing(pro, subscription: subscription(channel: "iyzico")))?.contains("web üzerinden") == true)
        XCTAssertTrue(PlanScreen.managedElsewhere(billing(pro, subscription: subscription(channel: "manual")))?.contains("destek") == true)
    }

    func testStatusLine() {
        XCTAssertTrue(PlanHero.statusLine(billing()).hasPrefix("Kullanım "))
        XCTAssertTrue(PlanHero.statusLine(billing(pro, subscription: subscription())).contains("tarihinde yenilenir"))
        XCTAssertTrue(PlanHero.statusLine(billing(pro, subscription: subscription(cancel: true))).contains("tarihine kadar geçerli"))
        XCTAssertTrue(PlanHero.statusLine(billing(free, subscription: subscription(status: "past_due"))).contains("Son ödeme alınamadı"))
    }
}

@MainActor
final class BillingStoreTests: XCTestCase {
    private var storefront: FakeGateway!
    private var backend: FakeBillingAPI!
    private var store: BillingStore!

    override func setUp() async throws {
        storefront = FakeGateway()
        backend = FakeBillingAPI()
        store = BillingStore(storefront: storefront, api: backend.api)
        await store.load()
    }

    func testLoadShowsPlansWithAppStorePrices() {
        XCTAssertEqual(store.plans.map(\.code), ["free", "pro", "business"])
        XCTAssertEqual(store.price(for: free), "Ücretsiz")
        XCTAssertEqual(store.price(for: pro), "₺229,00")
        XCTAssertEqual(store.action(for: pro), .buy)
        XCTAssertEqual(store.action(for: free), .current)
    }

    func testPriceFallsBackToTheCatalogWhenTheProductIsMissing() async {
        storefront.priceList = ["pro.monthly": "₺229,00"]
        await store.load()
        XCTAssertEqual(store.price(for: business), "829 TL")
        XCTAssertEqual(store.action(for: business), .unavailable)
    }

    func testPurchaseDeliversTheTransactionAndFinishesIt() async {
        storefront.purchaseResult = .success(.purchased(storefront.transaction("jws-1")))
        await store.purchase(pro)
        XCTAssertEqual(storefront.purchased, ["pro.monthly"])
        XCTAssertEqual(backend.attached, ["jws-1"])
        XCTAssertEqual(storefront.finished, ["jws-1"])
        XCTAssertEqual(store.billing?.plan.code, "pro")
        XCTAssertEqual(store.notice?.tone, .success)
        XCTAssertNil(store.purchasing)
    }

    func testCancelledPurchaseChangesNothing() async {
        storefront.purchaseResult = .success(.cancelled)
        await store.purchase(pro)
        XCTAssertTrue(backend.attached.isEmpty)
        XCTAssertNil(store.notice)
        XCTAssertEqual(store.billing?.plan.code, "free")
    }

    func testPendingPurchaseIsExplained() async {
        storefront.purchaseResult = .success(.pending)
        await store.purchase(pro)
        XCTAssertEqual(store.notice?.tone, .info)
        XCTAssertTrue(backend.attached.isEmpty)
    }

    func testTransactionStaysUnfinishedWhenTheAPIIsUnreachable() async {
        backend.attachError = .offline
        storefront.purchaseResult = .success(.purchased(storefront.transaction("jws-1")))
        await store.purchase(pro)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertEqual(store.notice?.tone, .error)
    }

    func testTransactionIsFinishedWhenTheAPIRejectsItForGood() async {
        backend.attachError = .server(status: 409, detail: "subscription_exists")
        storefront.purchaseResult = .success(.purchased(storefront.transaction("jws-1")))
        await store.purchase(pro)
        XCTAssertEqual(storefront.finished, ["jws-1"])
        XCTAssertEqual(store.notice?.tone, .error)
        XCTAssertTrue(store.notice?.text.contains("başka bir kanaldan") == true)
    }

    func testServerErrorKeepsTheTransactionForARetry() async {
        backend.attachError = .server(status: 503, detail: nil)
        storefront.purchaseResult = .success(.purchased(storefront.transaction("jws-1")))
        await store.purchase(pro)
        XCTAssertTrue(storefront.finished.isEmpty)
    }

    func testStoreErrorsAreReported() async {
        storefront.purchaseResult = .failure(PurchaseError.productUnavailable)
        await store.purchase(pro)
        XCTAssertEqual(store.notice?.tone, .error)
        XCTAssertTrue(backend.attached.isEmpty)
    }

    func testRestoreDeliversCurrentEntitlements() async {
        storefront.owned = [storefront.transaction("jws-owned")]
        await store.restore()
        XCTAssertEqual(backend.attached, ["jws-owned"])
        XCTAssertEqual(storefront.finished, ["jws-owned"])
        XCTAssertEqual(store.notice?.tone, .success)
        XCTAssertEqual(store.billing?.plan.code, "pro")
        XCTAssertFalse(store.restoring)
    }

    func testRestoreWithNothingToRestore() async {
        await store.restore()
        XCTAssertEqual(store.notice?.tone, .info)
        XCTAssertTrue(backend.attached.isEmpty)
    }

    func testRestoreReportsAnAppStoreFailure() async {
        storefront.syncError = PurchaseError.unverified
        storefront.owned = [storefront.transaction("jws-owned")]
        await store.restore()
        XCTAssertEqual(store.notice?.tone, .error)
        XCTAssertTrue(backend.attached.isEmpty)
    }

    func testUpdatesAreDeliveredInTheBackground() async throws {
        store.startListening()
        try await Task.sleep(for: .milliseconds(50))
        storefront.emit(storefront.transaction("jws-late"))
        for _ in 0..<40 where backend.attached.isEmpty { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(backend.attached, ["jws-late"])
        for _ in 0..<40 where storefront.finished.isEmpty { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(storefront.finished, ["jws-late"])
        store.reset()
    }

    func testErrorMessages() {
        XCTAssertTrue(BillingStore.message(for: APIError.server(status: 409, detail: "transaction_belongs_to_another_company")).contains("başka bir şirkete"))
        XCTAssertTrue(BillingStore.message(for: APIError.server(status: 403, detail: "Manager role required")).contains("şirket sahibi"))
        XCTAssertEqual(BillingStore.message(for: APIError.offline), APIError.offline.message)
    }
}

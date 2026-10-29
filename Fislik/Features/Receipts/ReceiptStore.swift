import Foundation
import Observation

/// Everything the client screens know about one month.
struct MonthState: Equatable {
    var receipts: [Receipt] = []
    var summary: MonthSummary = .empty
    var lock = PeriodLock(locked: false, lockedAt: nil)
    var submission: SubmissionState?
    var loaded = false
    var updatedAt: Date?
}

/// Shared client-side receipt state: month lists, summaries, credits, polling and mutations.
@MainActor
@Observable
final class ReceiptStore {
    static let shared = ReceiptStore()

    private(set) var months: [Period: MonthState] = [:]
    private(set) var credits: Credits?
    private(set) var grants: [Grant] = []
    var error: APIError?
    var offline = false
    /// When set, the store reads/writes on behalf of this client (accountant mode).
    var clientId: String?

    private var pollTask: Task<Void, Never>?

    func state(_ period: Period) -> MonthState { months[period] ?? MonthState() }

    var activeAccountant: Grant? { grants.first { $0.status == .active } }

    // MARK: Loading

    func load(_ period: Period, force: Bool = false) async {
        if !force, let m = months[period], m.loaded, let at = m.updatedAt, Date().timeIntervalSince(at) < 20 { return }
        if months[period] == nil, let cached = SessionCache.load(CachedMonth.self, key: cacheKey(period)) {
            months[period] = MonthState(receipts: cached.receipts, summary: cached.summary, lock: cached.lock, submission: cached.submission, loaded: true, updatedAt: cached.savedAt)
        }
        do {
            async let receipts = API.receipts(period)
            async let summary = API.summary(period)
            async let lock = API.periodLock(period)
            async let submission = try? API.submission(period)
            var state = MonthState(receipts: try await receipts, summary: try await summary, lock: try await lock, submission: await submission, loaded: true, updatedAt: Date())
            if state.receipts.isEmpty { state.summary = .empty }
            months[period] = state
            error = nil
            offline = false
            SessionCache.store(CachedMonth(state: state), key: cacheKey(period))
            WidgetSnapshot.update(from: self, period: period)
        } catch let e as APIError {
            if e == .offline || { if case .transport = e { return true }; return false }() { offline = true }
            if months[period]?.loaded != true { error = e }
        } catch {}
        schedulePolling()
    }

    func refreshCredits() async {
        if let c = try? await API.credits() { credits = c }
    }

    func refreshGrants() async {
        if let g = try? await API.grants() { grants = g }
    }

    func refreshAll(_ period: Period) async {
        async let a: Void = load(period, force: true)
        async let b: Void = refreshCredits()
        async let c: Void = refreshGrants()
        _ = await (a, b, c)
    }

    /// The web app polls every 5s while any extraction is pending; do the same.
    private func schedulePolling() {
        let pending = months.filter { $0.value.receipts.contains { $0.extraction?.status == .pending } }.map(\.key)
        pollTask?.cancel()
        guard !pending.isEmpty else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            for period in pending { await self.load(period, force: true) }
            await self.refreshCredits()
        }
    }

    private func cacheKey(_ period: Period) -> String { "month-\(period.raw)" }

    // MARK: Lookup

    func receipt(id: String) -> (Receipt, Period)? {
        for (period, state) in months {
            if let r = state.receipts.first(where: { $0.id == id }) { return (r, period) }
        }
        return nil
    }

    /// Receipts from every loaded month (newest month first) for search.
    var allLoaded: [(Period, Receipt)] {
        months.keys.sorted(by: >).flatMap { p in months[p]!.receipts.map { (p, $0) } }
    }

    // MARK: Local mutation helpers

    func upsert(_ receipt: Receipt) {
        let period = Period(receipt.period) ?? .current
        var state = months[period] ?? MonthState()
        if let i = state.receipts.firstIndex(where: { $0.id == receipt.id }) {
            state.receipts[i] = receipt
        } else {
            state.receipts.insert(receipt, at: 0)
        }
        months[period] = state
        schedulePolling()
    }

    private func remove(_ id: String) {
        for (p, var s) in months {
            s.receipts.removeAll { $0.id == id }
            months[p] = s
        }
    }

    private func update(_ id: String, _ change: (inout Receipt) -> Void) {
        for (p, var s) in months {
            if let i = s.receipts.firstIndex(where: { $0.id == id }) {
                change(&s.receipts[i])
                months[p] = s
            }
        }
    }

    // MARK: Mutations

    func delete(_ receipt: Receipt) async throws {
        try await API.deleteReceipt(receipt.id)
        remove(receipt.id)
        if let p = Period(receipt.period) { await load(p, force: true) }
    }

    func move(_ receipt: Receipt, to period: Period) async throws {
        let moved = try await API.moveReceipt(receipt.id, to: period)
        remove(receipt.id)
        upsert(moved)
        if let from = Period(receipt.period) { await load(from, force: true) }
        await load(period, force: true)
    }

    func patch(_ receipt: Receipt, _ patch: ExtractionPatch) async throws {
        let extraction = try await API.patchExtraction(receipt.id, patch)
        update(receipt.id) { $0.extraction = extraction }
        if let p = Period(receipt.period) { await load(p, force: true) }
    }

    func reanalyze(_ receipt: Receipt) async throws {
        let extraction = try await API.reanalyze(receipt.id)
        update(receipt.id) { $0.extraction = extraction }
        await refreshCredits()
        schedulePolling()
    }

    func retry(_ receipt: Receipt) async throws {
        let extraction = try await API.retryExtraction(receipt.id)
        update(receipt.id) { $0.extraction = extraction }
        schedulePolling()
    }

    func resolveIssue(_ receipt: Receipt) async throws {
        guard let issue = receipt.openIssue else { return }
        try await API.resolveIssue(issue.id)
        update(receipt.id) { $0.openIssue = nil }
    }

    func submit(_ period: Period) async throws {
        let state = try await API.submit(period)
        months[period]?.submission = state
    }

    func reset() {
        months = [:]
        credits = nil
        grants = []
        pollTask?.cancel()
    }
}

/// Disk representation of a month for offline display.
struct CachedMonth: Codable {
    var receipts: [Receipt]
    var summary: MonthSummary
    var lock: PeriodLock
    var submission: SubmissionState?
    var savedAt: Date

    init(state: MonthState) {
        receipts = state.receipts
        summary = state.summary
        lock = state.lock
        submission = state.submission
        savedAt = Date()
    }
}

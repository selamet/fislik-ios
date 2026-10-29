import Foundation
import Observation
import SwiftUI

/// In-app notifications: list, unread count, 60s foreground polling, badge sync.
@MainActor
@Observable
final class NotificationsStore {
    static let shared = NotificationsStore()

    private(set) var items: [AppNotification] = []
    private(set) var unreadCount = 0
    private(set) var loaded = false
    var error: APIError?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored weak var app: AppModel?

    func refresh() async {
        do {
            let page = try await API.notifications(limit: 50)
            items = page.items
            unreadCount = page.unreadCount
            loaded = true
            error = nil
            SessionCache.store(items, key: "notifications")
            sync()
        } catch let e as APIError {
            if !loaded, let cached = SessionCache.load([AppNotification].self, key: "notifications") {
                items = cached
                unreadCount = cached.filter { !$0.read }.count
                loaded = true
            }
            error = e
        } catch {}
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    func markRead(_ ids: [String]) async {
        let targets = Set(ids)
        let changed = items.filter { targets.contains($0.id) && !$0.read }.count
        guard changed > 0 else { return }
        for i in items.indices where targets.contains(items[i].id) { items[i].read = true }
        unreadCount = max(0, unreadCount - changed)
        sync()
        try? await API.markRead(ids)
    }

    func markAllRead() async {
        for i in items.indices { items[i].read = true }
        unreadCount = 0
        sync()
        try? await API.markRead(nil)
    }

    private func sync() {
        app?.unreadCount = unreadCount
        PushManager.shared.setBadge(unreadCount)
    }

    func reset() {
        pollTask?.cancel()
        items = []
        unreadCount = 0
        loaded = false
    }
}

/// Display model for one notification row.
struct NotificationContent {
    enum Tone { case warning, success, neutral, brand }

    let icon: FIcon
    let tone: Tone
    let text: String
    var meta: String?
    var link: AppModel.DeepLink?
    var linkTitle: String?

    var color: Color {
        switch tone {
        case .warning: FColor.warning
        case .success: FColor.success
        case .neutral: FColor.muted
        case .brand: FColor.brand
        }
    }

    @MainActor
    init(_ n: AppNotification, isAccountant: Bool, accountantName: String?) {
        let p = n.payload
        let name = p["name"]?.string ?? p["accountant_name"]?.string ?? p["client_name"]?.string ?? "Biri"
        let period = p["period"]?.string.flatMap(Period.init)
        switch n.type {
        case "issue_opened":
            icon = .triangleAlert
            tone = .warning
            let who = accountantName ?? "Muhasebecin"
            text = "\(who) bir fişin için soru sordu: “\(p["message"]?.string ?? "")”"
            if let id = p["receipt_id"]?.string {
                link = .receipt(id: id, period: period)
                linkTitle = "Fişe git →"
                if let (r, _) = ReceiptStore.shared.receipt(id: id) {
                    meta = "\(r.merchant) · \(TR.money(r.total))"
                }
            }
        case "issue_resolved":
            icon = .circleCheck
            tone = .success
            text = "Mükellefin bir fişteki soruyu yanıtladı\(period.map { " · \($0.title)" } ?? "")"
        case "receipts_processed":
            icon = .circleCheck
            tone = .success
            text = "\(p["accountant_name"]?.string ?? name), \(period?.title ?? "") fişlerinizi işledi (\(p["processed_count"]?.int ?? 0) fiş)"
            link = period.map { .month($0) }
        case "period_locked":
            icon = .lock
            tone = .neutral
            text = "\(p["accountant_name"]?.string ?? name), \(period?.title ?? "") döneminizi kapattı"
            link = period.map { .month($0) }
        case "receipts_submitted":
            icon = .inbox
            tone = .success
            text = "\(p["client_name"]?.string ?? name), \(period?.title ?? "") fişlerini gönderdi (\(p["receipt_count"]?.int ?? 0) fiş)"
        case "invite_accepted":
            icon = .userCheck
            tone = .success
            text = "\(name) davetini kabul etti"
        case "invite_declined":
            icon = .x
            tone = .neutral
            text = "\(name) davetini reddetti"
        case "grant_invite":
            icon = .userPlus
            tone = .brand
            text = p["role"]?.string == "accountant"
                ? "\(name) muhasebecin olarak fişlerini görmek istiyor"
                : "\(name) seni muhasebecisi olarak eklemek istiyor"
            linkTitle = "Davete bak →"
        default:
            icon = .bell
            tone = .neutral
            text = "Yeni bildirim"
        }
    }
}

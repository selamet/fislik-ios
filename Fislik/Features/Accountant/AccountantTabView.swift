import SwiftUI

enum AccountantRoute: Hashable {
    case client(id: String, name: String)
    case receipt(id: String, clientId: String)
}

@MainActor
@Observable
final class AccountantRouter {
    enum Tab: Hashable { case clients, notifications, profile }

    var tab: Tab = .clients
    var clientsPath: [AccountantRoute] = []
    var profilePath: [ClientRoute] = []
    var period: Period = .current
    var inviting = false
    /// Client-scoped stores, kept so detail screens share state with the month grid.
    @ObservationIgnored private var stores: [String: ReceiptStore] = [:]

    func store(for clientId: String) -> ReceiptStore {
        if let s = stores[clientId] { return s }
        let s = ReceiptStore.forClient(clientId)
        stores[clientId] = s
        return s
    }
}

/// Accountant shell: Mükellefler / Bildirimler / Profil.
struct AccountantTabView: View {
    @Environment(AppModel.self) private var app
    @State private var router = AccountantRouter()
    @State private var clients = ClientsStore()

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            ZStack {
                tab(.clients) {
                    NavigationStack(path: $router.clientsPath) {
                        ClientsScreen()
                            .navigationDestination(for: AccountantRoute.self) { route in
                                switch route {
                                case .client(let id, let name): ClientMonthView(clientId: id, name: name)
                                case .receipt(let id, let clientId): ReceiptDetailView(id: id, store: router.store(for: clientId))
                                }
                            }
                    }
                }
                tab(.notifications) {
                    NavigationStack {
                        NotificationsScreen { n, _ in open(n) }
                    }
                }
                tab(.profile) {
                    NavigationStack(path: $router.profilePath) {
                        ProfileScreen { router.profilePath.append($0) }
                            .navigationDestination(for: ClientRoute.self) { route in
                                switch route {
                                case .credits: CreditsView()
                                case .notificationPrefs: NotificationPrefsView()
                                case .changePassword: ChangePasswordView()
                                default: EmptyView()
                                }
                            }
                    }
                }
            }
            if pathEmpty {
                FTabBar(items: [
                    FTabItem(tab: .clients, title: "Mükellefler", icon: .users),
                    FTabItem(tab: .notifications, title: "Bildirimler", icon: .bell, badge: app.unreadCount),
                    FTabItem(tab: .profile, title: "Profil", icon: .user),
                ], selection: $router.tab)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.2), value: pathEmpty)
        .ignoresSafeArea(.keyboard)
        .environment(router)
        .environment(clients)
        .sheet(isPresented: $router.inviting) {
            InviteSheet(invitingAccountant: false) { Task { await clients.load(router.period, force: true) } }
        }
        .onAppear(perform: consumeLink)
        .onChange(of: app.pendingLink) { consumeLink() }
    }

    private var pathEmpty: Bool {
        switch router.tab {
        case .clients: router.clientsPath.isEmpty
        case .profile: router.profilePath.isEmpty
        case .notifications: true
        }
    }

    private func tab(_ t: AccountantRouter.Tab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(router.tab == t ? 1 : 0)
            .allowsHitTesting(router.tab == t)
            .accessibilityHidden(router.tab != t)
    }

    private func open(_ n: AppNotification) {
        let clientId = n.payload["client_id"]?.string
        let period = n.payload["period"]?.string.flatMap(Period.init)
        if let period { router.period = period }
        router.tab = .clients
        if let clientId {
            let name = clients.clients.first { $0.clientId == clientId }?.fullName ?? n.payload["client_name"]?.string ?? "Mükellef"
            router.clientsPath = [.client(id: clientId, name: name)]
            if n.type == "issue_resolved", let rid = n.payload["receipt_id"]?.string {
                router.clientsPath.append(.receipt(id: rid, clientId: clientId))
            }
        }
    }

    private func consumeLink() {
        switch app.pendingLink {
        case .notifications?: router.tab = .notifications
        case .month(let p)?: router.period = p; router.tab = .clients
        case .invite(let token)?:
            Task { _ = try? await API.acceptInvite(token: token); await clients.load(router.period, force: true) }
        default: return
        }
        app.pendingLink = nil
    }
}

/// Accountant's client list + pending client invites for a month.
@MainActor
@Observable
final class ClientsStore {
    private(set) var clients: [ClientSummary] = []
    private(set) var grants: [Grant] = []
    private(set) var loaded = false
    private(set) var period: Period = .current
    var error: APIError?

    func load(_ period: Period, force: Bool = false) async {
        if !force && loaded && self.period == period { return }
        self.period = period
        do {
            async let c = API.clients(period)
            async let g = API.grants()
            clients = try await c
            grants = (try? await g) ?? grants
            loaded = true
            error = nil
            SessionCache.store(clients, key: "clients-\(period.raw)")
        } catch let e as APIError {
            if let cached = SessionCache.load([ClientSummary].self, key: "clients-\(period.raw)") { clients = cached; loaded = true }
            error = e
        } catch {}
    }

    func refreshGrants() async {
        if let g = try? await API.grants() { grants = g }
    }
}

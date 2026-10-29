import SwiftUI

/// Client shell: Fişler / Muhasebecim / Bildirimler / Profil.
struct ClientTabView: View {
    @Environment(AppModel.self) private var app
    @State private var router = ClientRouter()
    @State private var uploads = UploadQueue()

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            ZStack {
                tab(.receipts) {
                    NavigationStack(path: $router.receiptsPath) {
                        HomeView().navigationDestination(for: ClientRoute.self, destination: destination)
                    }
                }
                tab(.accountant) {
                    NavigationStack { AccountantScreen() }
                }
                tab(.notifications) {
                    NavigationStack(path: $router.notificationsPath) {
                        NotificationsScreen().navigationDestination(for: ClientRoute.self, destination: destination)
                    }
                }
                tab(.profile) {
                    NavigationStack(path: $router.profilePath) {
                        ProfileScreen().navigationDestination(for: ClientRoute.self, destination: destination)
                    }
                }
            }
            FTabBar(items: [
                FTabItem(tab: .receipts, title: "Fişler", icon: .receipt),
                FTabItem(tab: .accountant, title: "Muhasebecim", icon: .users),
                FTabItem(tab: .notifications, title: "Bildirimler", icon: .bell, badge: app.unreadCount),
                FTabItem(tab: .profile, title: "Profil", icon: .user),
            ], selection: $router.tab)
        }
        .ignoresSafeArea(.keyboard)
        .environment(router)
        .environment(uploads)
        .sheet(item: Binding(get: { router.sheet == .camera ? nil : router.sheet }, set: { router.sheet = $0 })) { sheet in
            switch sheet {
            case .addReceipt: AddReceiptSheet()
            case .submit: SubmitMonthSheet()
            case .inviteAccountant: InviteAccountantSheet()
            case .camera: EmptyView()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { router.sheet == .camera }, set: { if !$0 { router.sheet = nil } })) {
            CameraScreen()
        }
        .onAppear(perform: consumeLink)
        .onChange(of: app.pendingLink) { consumeLink() }
    }

    private func tab(_ t: ClientRouter.Tab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(router.tab == t ? 1 : 0)
            .allowsHitTesting(router.tab == t)
            .accessibilityHidden(router.tab != t)
    }

    @ViewBuilder
    private func destination(_ route: ClientRoute) -> some View {
        switch route {
        case .receipt(let id): ReceiptDetailView(id: id)
        case .search: SearchView()
        case .credits: CreditsView()
        case .company: CompanyFormView(mode: .edit)
        case .notificationPrefs: NotificationPrefsView()
        case .changePassword: ChangePasswordView()
        }
    }

    private func consumeLink() {
        guard let link = app.pendingLink else { return }
        switch link {
        case .receipt(let id, let period):
            if let period { router.period = period }
            router.tab = .receipts
            router.receiptsPath = [.receipt(id: id)]
        case .camera:
            router.tab = .receipts
            router.sheet = .camera
        case .notifications:
            router.tab = .notifications
        case .month(let p):
            router.tab = .receipts
            router.receiptsPath = []
            router.period = p
        case .invite(let token):
            router.tab = .accountant
            Task { _ = try? await API.acceptInvite(token: token); await ReceiptStore.shared.refreshGrants() }
        case .passwordReset:
            return
        }
        app.pendingLink = nil
    }
}

extension ClientSheet: Equatable {}

import SwiftUI

/// Client shell: Fişler / Şirket / Bildirimler / Profil. The second tab is
/// the company screen for owners and admins; with an API that has no
/// companies yet it stays the legacy "Muhasebecim" screen.
struct ClientTabView: View {
    @Environment(AppModel.self) private var app
    @State private var router = ClientRouter()
    @State private var uploads = UploadQueue.shared
    @State private var companies = CompanyStore.shared

    private var isUploader: Bool { companies.active?.role == .uploader }
    private var showsCompanyTab: Bool { companies.active != nil && !isUploader }

    /// Uploaders get three tabs: nothing to manage on the company, and the
    /// accountant link is the managers' business.
    private var tabItems: [FTabItem<ClientRouter.Tab>] {
        var items = [FTabItem(tab: ClientRouter.Tab.receipts, title: "Fişler", icon: .receipt)]
        if !isUploader {
            items.append(showsCompanyTab
                ? FTabItem(tab: .accountant, title: "Şirket", icon: .building)
                : FTabItem(tab: .accountant, title: "Muhasebecim", icon: .users))
        }
        items.append(FTabItem(tab: .notifications, title: "Bildirimler", icon: .bell, badge: app.unreadCount))
        items.append(FTabItem(tab: .profile, title: "Profil", icon: .user))
        return items
    }

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
                    if showsCompanyTab {
                        NavigationStack(path: $router.companyPath) {
                            CompanyScreen().navigationDestination(for: ClientRoute.self, destination: destination)
                        }
                    } else {
                        NavigationStack { AccountantScreen() }
                    }
                }
                tab(.notifications) {
                    NavigationStack(path: $router.notificationsPath) {
                        NotificationsScreen { n, content in
                            if let link = content.link {
                                app.pendingLink = link
                            } else if n.type == "grant_invite" || n.type.hasPrefix("invite_") {
                                router.tab = .accountant
                            }
                        }
                        .navigationDestination(for: ClientRoute.self, destination: destination)
                    }
                }
                tab(.profile) {
                    NavigationStack(path: $router.profilePath) {
                        ProfileScreen { router.profilePath.append($0) }.navigationDestination(for: ClientRoute.self, destination: destination)
                    }
                }
            }
            if activePathEmpty {
            FTabBar(items: tabItems, selection: $router.tab)
            .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.2), value: activePathEmpty)
        .ignoresSafeArea(.keyboard)
        .sheet(item: Binding(get: { router.sheet == .camera ? nil : router.sheet }, set: { router.sheet = $0 })) { sheet in
            switch sheet {
            case .addReceipt: AddReceiptSheet()
            case .submit: SubmitMonthSheet()
            case .inviteAccountant: InviteAccountantSheet()
            case .companySwitcher: CompanySwitcherSheet()
            case .inviteMember: InviteMemberSheet()
            case .camera: EmptyView()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { router.sheet == .camera }, set: { if !$0 { router.sheet = nil } })) {
            CameraScreen()
        }
        .fullScreenCover(item: $router.memberInvite) { source in
            AcceptMemberInviteView(source: source)
        }
        // After the presentation modifiers so sheets and covers inherit them too.
        .environment(router)
        .environment(uploads)
        .onAppear(perform: consumeLink)
        .onChange(of: isUploader) { _, uploader in
            if uploader && router.tab == .accountant { router.tab = .receipts }
        }
        .onChange(of: app.pendingLink) { consumeLink() }
    }

    /// Pushed screens (detail, search, settings pages) hide the tab bar, as in the design.
    private var activePathEmpty: Bool {
        switch router.tab {
        case .receipts: router.receiptsPath.isEmpty
        case .notifications: router.notificationsPath.isEmpty
        case .profile: router.profilePath.isEmpty
        case .accountant: router.companyPath.isEmpty
        }
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
        case .accountants: AccountantScreen()
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
        case .memberInvite(let token):
            router.memberInvite = .token(token)
        case .memberInviteId(let id):
            Task {
                await companies.loadInvites()
                if let invite = companies.invites.first(where: { $0.id == id }) {
                    router.memberInvite = .invite(invite)
                }
            }
        case .passwordReset:
            return
        }
        app.pendingLink = nil
    }
}

extension ClientSheet: Equatable {}

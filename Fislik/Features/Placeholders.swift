import SwiftUI

// Temporary screens; each one is replaced by its feature issue.

struct CompanySetupView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Button("Şimdilik geç") { app.companyDone(skipped: true) }.buttonStyle(.fSecondary).padding()
    }
}

struct ClientTabView: View {
    enum Tab { case receipts, accountant, notifications, profile }
    @State private var tab = Tab.receipts

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Fişler").fFont(30, .heavy)
            Spacer()
            FTabBar(items: [
                FTabItem(tab: .receipts, title: "Fişler", icon: .receipt),
                FTabItem(tab: .accountant, title: "Muhasebecim", icon: .users),
                FTabItem(tab: .notifications, title: "Bildirimler", icon: .bell),
                FTabItem(tab: .profile, title: "Profil", icon: .user),
            ], selection: $tab)
        }
    }
}

struct AccountantTabView: View {
    var body: some View { Text("Mükellefler").fFont(30, .heavy) }
}

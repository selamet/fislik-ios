import SwiftUI

/// 2AE — "Mükellefler".
struct ClientsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountantRouter.self) private var router
    @Environment(ClientsStore.self) private var store
    @State private var notifications = NotificationsStore.shared
    @State private var query = ""
    @State private var busy: String?

    var body: some View {
        let period = router.period
        let filtered = store.clients.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }
        let submissions = notifications.items.filter { $0.type == "receipts_submitted" && $0.payload["period"]?.string == period.raw }
        let submittedClients = Set(submissions.compactMap { $0.payload["client_id"]?.string })
        let incoming = store.grants.filter { $0.status == .pending && $0.direction == .incoming }

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    FislikLogo(subtitle: "MUHASEBECİ")
                    Spacer()
                    FIconButton(icon: .userPlus) { router.inviting = true }.accessibilityLabel("Mükellef davet et")
                    FIconButton(icon: .bell, badge: app.unreadCount > 0 ? (app.unreadCount > 9 ? "9+" : "\(app.unreadCount)") : nil) { router.tab = .notifications }
                }
                .frame(height: 44)

                MonthTitleBar(period: period, canGoNext: period < .current, onChange: { p in withAnimation(.snappy) { router.period = p } }) {
                    Text("MÜKELLEFLER · \(store.clients.count)").fFont(11, .heavy, tracking: 0.4).foregroundStyle(FColor.muted)
                }
                .padding(.top, 6)

                HStack(spacing: 8) {
                    FStatTile(title: "TOPLAM FİŞ", value: "\(store.clients.reduce(0) { $0 + $1.receiptCount })")
                    FStatTile(title: "İŞLENMEMİŞ", value: "\(store.clients.reduce(0) { $0 + $1.unprocessedCount })", valueColor: FColor.warning)
                    FStatTile(title: "GÖNDERİLDİ", value: "\(submittedClients.count)", suffix: "/\(store.clients.count)")
                }

                ForEach(incoming) { g in
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            FIconTile(icon: .userPlus, size: 38, iconSize: 18)
                            (Text(g.displayName).fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" seni muhasebecisi olarak eklemek istiyor."))
                                .fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            Button("Kabul Et") { act(g) { _ = try await API.acceptGrant(g.id) } }.buttonStyle(.f(.primary, height: 38, fontSize: 13, radius: 11))
                            Button("Reddet") { act(g) { try await API.declineGrant(g.id) } }.buttonStyle(.f(.dangerOutline, height: 38, fontSize: 13, radius: 11))
                        }
                        .disabled(busy != nil)
                    }
                    .padding(12)
                    .background(FColor.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.brand.opacity(0.25)))
                }

                if let latest = submissions.first, let cid = latest.payload["client_id"]?.string {
                    let name = latest.payload["client_name"]?.string ?? "Mükellef"
                    Button { router.clientsPath.append(.client(id: cid, name: name)) } label: {
                        HStack(spacing: 10) {
                            Icon(.inbox, size: 17).foregroundStyle(FColor.brand)
                            (Text(name).fontWeight(.heavy) + Text(" \(period.monthName) fişlerini gönderdi · \(latest.payload["receipt_count"]?.int ?? 0) fiş"))
                                .fFont(12.5, .semibold)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Text("İncele").fFont(12, .heavy).foregroundStyle(FColor.brand)
                        }
                        .foregroundStyle(FColor.ink)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(FColor.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.brand.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Icon(.search, size: 14).foregroundStyle(FColor.muted)
                    TextField("Mükellef ara", text: $query).fFont(12.5, .semibold)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.lineStrong))

                if store.loaded && store.clients.isEmpty {
                    VStack(spacing: 12) {
                        Text("Henüz mükellefin yok").fFont(16, .heavy)
                        Text("Mükelleflerini davet et; fişlerini yükledikçe burada görürsün.").fFont(13, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.center)
                        Button { router.inviting = true } label: { FButtonLabel(title: "Mükellef davet et", icon: .userPlus) }
                            .buttonStyle(.f(.primary, height: 46, fontSize: 14)).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if let error = store.error, !store.loaded {
                    LoadErrorView(error: error) { Task { await store.load(period, force: true) } }
                } else {
                    FGroupedCard {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RowDivider() }
                            Button { router.clientsPath.append(.client(id: c.clientId, name: c.fullName)) } label: { row(c) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .refreshable {
            await store.load(router.period, force: true)
            await notifications.refresh()
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: router.period) { await store.load(router.period) }
    }

    private func row(_ c: ClientSummary) -> some View {
        HStack(spacing: 12) {
            FAvatar(initials: c.fullName.initials, size: 42, radius: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.fullName).fFont(14, .heavy).lineLimit(1)
                Text("\(c.receiptCount) fiş · \(c.lastUploadAt.map(TR.longDay) ?? "—")").fFont(11.5, .semibold).foregroundStyle(FColor.muted)
            }
            Spacer(minLength: 4)
            if c.unprocessedCount > 0 {
                FStatusBadge(text: "\(c.unprocessedCount) işlenmemiş", color: FColor.warning)
            }
            Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func act(_ g: Grant, _ work: @escaping () async throws -> Void) {
        busy = g.id
        Task {
            defer { busy = nil }
            try? await work()
            await store.load(router.period, force: true)
        }
    }
}

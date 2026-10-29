import SwiftUI

/// Remembers when a grant was first seen in a given state (the API has no timestamps on grants).
enum GrantDates {
    private static let key = "grantDates"

    static func date(for grant: Grant) -> Date {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let k = "\(grant.id)-\(grant.status.rawValue)"
        if let t = map[k] { return Date(timeIntervalSince1970: t) }
        let now = Date()
        map[k] = now.timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: key)
        return now
    }

    static var recentEmails: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentInviteEmails") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(3)), forKey: "recentInviteEmails") }
    }
}

/// 2V / 2AD — client's accountant connections.
struct AccountantScreen: View {
    @Environment(ClientRouter.self) private var router
    @State private var store = ReceiptStore.shared
    @State private var loaded = false
    @State private var busyId: String?
    @State private var error: String?
    @State private var revoking: Grant?

    var body: some View {
        let grants = store.grants
        let incoming = grants.filter { $0.status == .pending && $0.direction == .incoming }
        let active = grants.filter { $0.status == .active }
        let outgoing = grants.filter { $0.status == .pending && $0.direction == .outgoing }

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(grants.isEmpty && loaded ? "" : "BAĞLANTILAR").fFont(11, .heavy, tracking: 0.4).foregroundStyle(FColor.muted)
                        Spacer()
                        if !(grants.isEmpty && loaded) {
                            Button { router.sheet = .inviteAccountant } label: {
                                HStack(spacing: 6) {
                                    Icon(.userPlus, size: 15)
                                    Text("Davet et")
                                }
                                .fFont(12.5, .bold)
                                .foregroundStyle(FColor.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(FColor.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 44)
                    Text("Muhasebecim").fFont(30, .heavy, tracking: -0.9)

                    if let error { FBanner(icon: .circleAlert, tone: .danger, text: Text(error)) }

                    if grants.isEmpty && loaded {
                        EmptyAccountantView { router.sheet = .inviteAccountant }
                    }
                    ForEach(incoming) { incomingCard($0) }
                    ForEach(active) { activeCard($0) }
                    ForEach(outgoing) { outgoingCard($0) }
                    if !grants.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Icon(.shieldCheck, size: 16).foregroundStyle(FColor.brand).padding(.top, 2)
                            (Text("Muhasebecin fişlerini ") + Text("yalnızca görüntüleyebilir ve indirebilir").fontWeight(.bold).foregroundColor(FColor.ink) + Text(". Silme yetkisi yoktur; erişimi dilediğin an kaldırabilirsin."))
                                .fFont(12, .medium).foregroundStyle(FColor.muted).lineSpacing(3)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fCard(radius: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .refreshable { await reload() }

            if let revoking {
                FDialog(icon: .x, tint: FColor.danger, title: "Erişimi iptal et", confirmTitle: "İptal et", confirmKind: .danger, busy: busyId == revoking.id, onCancel: { self.revoking = nil }, onConfirm: {
                    act(revoking) { try await API.revokeGrant(revoking.id) }
                    self.revoking = nil
                }) {
                    (Text(revoking.displayName).fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" artık fişlerini göremeyecek. İstediğin zaman yeniden davet edebilirsin."))
                        .dialogMessage()
                }
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .fStatusBarBackdrop()
        .toolbar(.hidden, for: .navigationBar)
        .task { await reload() }
    }

    private func reload() async {
        await store.refreshGrants()
        loaded = true
    }

    private func act(_ grant: Grant, _ work: @escaping () async throws -> Void) {
        busyId = grant.id
        error = nil
        Task {
            defer { busyId = nil }
            do {
                try await work()
                await store.refreshGrants()
            } catch let e as APIError {
                error = e.message
            } catch {}
        }
    }

    private func incomingCard(_ g: Grant) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                FIconTile(icon: .userPlus, size: 44, iconSize: 20)
                (Text(g.displayName).fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" muhasebeciniz olarak fiş ve faturalarınızı Fişlik üzerinden toplamak istiyor."))
                    .fFont(13, .semibold).foregroundStyle(FColor.muted).lineSpacing(3)
            }
            HStack(spacing: 8) {
                Button { act(g) { _ = try await API.acceptGrant(g.id) } } label: { FButtonLabel(title: "Kabul Et", loading: busyId == g.id) }
                    .buttonStyle(.f(.primary, height: 40, fontSize: 13, radius: 12))
                Button("Reddet") { act(g) { try await API.declineGrant(g.id) } }
                    .buttonStyle(.f(.dangerOutline, height: 40, fontSize: 13, radius: 12))
            }
            .disabled(busyId != nil)
        }
        .padding(14)
        .background(FColor.brand.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FColor.brand.opacity(0.25)))
    }

    private func activeCard(_ g: Grant) -> some View {
        let processed = store.months.values.reduce(0) { $0 + $1.receipts.filter(\.processed).count }
        let openIssues = store.months.values.reduce(0) { $0 + $1.receipts.filter { $0.openIssue != nil }.count }
        let prevSent = store.state(router.period.previous).submission?.lastSentAt != nil
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                FAvatar(initials: g.displayName.initials, size: 52, radius: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.displayName).fFont(15.5, .heavy)
                    Text(g.displayEmail).fFont(12, .semibold).foregroundStyle(FColor.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                FStatusBadge(text: "Aktif", color: FColor.success)
            }
            .padding(14)
            RowDivider()
            HStack(spacing: 0) {
                stat("BAĞLI", "\(TR.shortDay(GrantDates.date(for: g))) \(Calendar.fislik.component(.year, from: GrantDates.date(for: g)))")
                Rectangle().fill(FColor.ink.opacity(0.06)).frame(width: 1)
                stat("İŞLENEN", "\(processed) fiş")
                Rectangle().fill(FColor.ink.opacity(0.06)).frame(width: 1)
                stat("AÇIK SORU", "\(openIssues)", color: openIssues > 0 ? FColor.warning : FColor.ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            RowDivider()
            Button { router.tab = .receipts; router.sheet = .submit } label: {
                HStack(spacing: 12) {
                    Icon(.send, size: 17).foregroundStyle(FColor.brand)
                    Text("\(router.period.monthName) fişlerini gönder").fFont(13.5, .semibold)
                    Spacer()
                    if prevSent {
                        Text("\(router.period.previous.monthName) gönderildi").fFont(11.5, .semibold).foregroundStyle(FColor.muted)
                    }
                    Icon(.chevronRight, size: 15).foregroundStyle(FColor.muted)
                }
                .foregroundStyle(FColor.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowDivider()
            Button { revoking = g } label: {
                HStack(spacing: 12) {
                    Icon(.x, size: 17)
                    Text("Erişimi iptal et").fFont(13.5, .semibold)
                    Spacer()
                }
                .foregroundStyle(FColor.danger)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(FColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FColor.line))
    }

    private func stat(_ title: String, _ value: String, color: Color = FColor.ink) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).fFont(10, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
            Text(value).fFont(13, .bold).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func outgoingCard(_ g: Grant) -> some View {
        HStack(spacing: 12) {
            Icon(.clock, size: 17).foregroundStyle(FColor.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(g.invitedEmail).fFont(13.5, .bold).lineLimit(1)
                // One wrapping line like the design; "Tekrar gönder" is an inline link.
                Text("Davet gönderildi · \(TR.shortDay(GrantDates.date(for: g))) · [Tekrar gönder](fislik-action://resend)")
                    .fFont(11.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .tint(FColor.brand)
                    .environment(\.openURL, OpenURLAction { _ in
                        act(g) {
                            try await API.revokeGrant(g.id)
                            _ = try await API.invite(email: g.invitedEmail)
                        }
                        return .handled
                    })
            }
            Spacer(minLength: 4)
            FStatusBadge(text: "Bekliyor", color: FColor.warning)
            Button { act(g) { try await API.revokeGrant(g.id) } } label: {
                Icon(.x, size: 14).foregroundStyle(FColor.muted).frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Daveti iptal et")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .fCard(radius: 16)
    }
}

/// 2AD — no accountant yet.
struct EmptyAccountantView: View {
    let onInvite: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous).fill(FColor.brand.opacity(0.08))
                Icon(.users, size: 28)
                    .foregroundStyle(FColor.brand)
                    .frame(width: 64, height: 64)
                    .background(FColor.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: FColor.ink.opacity(0.12), radius: 12, y: 8)
                Icon(.plus, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FColor.brand, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .offset(x: 28, y: 28)
            }
            .frame(width: 132, height: 132)
            VStack(spacing: 6) {
                Text("Henüz muhasebeci eklemedin").fFont(18, .heavy, tracking: -0.3)
                Text("Muhasebecini davet et; fişlerini anında görsün, ay sonunda işlesin ve kapatsın.")
                    .fFont(13.5, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.center).lineSpacing(3)
            }
            Button(action: onInvite) { FButtonLabel(title: "Muhasebeci davet et", icon: .userPlus) }
                .buttonStyle(.f(.primary, height: 50, fontSize: 15, hPadding: 20))
                .fixedSize()
            (Text("Muhasebecin seni davet ettiyse ") + Text("Bildirimler").foregroundColor(FColor.brand).fontWeight(.bold) + Text("'de görünür."))
                .fFont(12, .semibold).foregroundStyle(FColor.muted)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}

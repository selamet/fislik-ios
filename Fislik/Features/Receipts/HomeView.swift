import SwiftUI

enum ClientRoute: Hashable {
    case receipt(id: String)
    case search
    case credits
    case company
    case notificationPrefs
    case changePassword
}

enum ClientSheet: Identifiable {
    case addReceipt
    case camera
    case submit
    case inviteAccountant

    var id: String { "\(self)" }
}

/// Navigation + presentation state shared across client tabs.
@MainActor
@Observable
final class ClientRouter {
    enum Tab: Hashable { case receipts, accountant, notifications, profile }

    var tab: Tab = .receipts
    var receiptsPath: [ClientRoute] = []
    var profilePath: [ClientRoute] = []
    var notificationsPath: [ClientRoute] = []
    var sheet: ClientSheet?
    var period: Period = .current

    func open(_ route: ClientRoute) {
        tab = .receipts
        receiptsPath.append(route)
    }
}

/// 2G / 2H / 2J / 2N — the client's month screen.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(ClientRouter.self) private var router
    @Environment(UploadQueue.self) private var uploads
    @State private var store = ReceiptStore.shared
    @State private var filter: ReceiptFilter = .all
    @AppStorage("homeLayout") private var listLayout = false

    private var period: Period { router.period }
    private var isOffline: Bool { store.offline || !Connectivity.shared.isOnline }
    private var month: MonthState { store.state(period) }

    var body: some View {
        @Bindable var router = router
        let receipts = month.receipts
        let visible = receipts.filter { $0.matches(filter) }
        let dupes = receipts.duplicateIds

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(receipts: receipts)
                    .padding(.bottom, 2)

                if !month.loaded, let error = store.error {
                    LoadErrorView(error: error, retry: { Task { await store.refreshAll(period) } }, onShowCache: store.hasCache(period) ? { store.showCache(period) } : nil)
                } else if month.loaded && receipts.isEmpty && uploads.items(for: period).isEmpty && !month.lock.locked {
                    EmptyMonthView(period: period, previous: store.state(period.previous)) {
                        router.sheet = .camera
                    } onGallery: {
                        router.sheet = .addReceipt
                    } onPrevious: {
                        change(period.previous)
                    }
                } else {
                    content(receipts: receipts, visible: visible, dupes: dupes)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await store.refreshAll(period) }
        .background(FColor.bg.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if !month.lock.locked {
                CameraFAB { router.sheet = .addReceipt }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let notice = uploads.notice {
                FToast(text: notice) { uploads.notice = nil }
            }
        }
        .onChange(of: Connectivity.shared.isOnline) { _, online in
            if online { Task { await store.load(period, force: true) } }
        }
        .task(id: period) {
            await store.load(period)
            if store.credits == nil { await store.refreshCredits() }
            if store.grants.isEmpty { await store.refreshGrants() }
            await store.load(period.previous)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            if value.translation.width < -60, period < .current { change(period.next) }
            if value.translation.width > 60 { change(period.previous) }
        })
    }

    private func change(_ p: Period) {
        guard p <= .current else { return }
        withAnimation(.snappy) { router.period = p }
        filter = .all
    }

    // MARK: Header

    @ViewBuilder
    private func header(receipts: [Receipt]) -> some View {
        HStack {
            FislikLogo()
            Spacer()
            if isOffline {
                OfflinePill()
            } else {
                HStack(spacing: 8) {
                    FIconButton(icon: .search) { router.receiptsPath.append(.search) }
                        .accessibilityLabel("Ara")
                    FIconButton(icon: .bell, badge: app.unreadCount > 0 ? (app.unreadCount > 9 ? "9+" : "\(app.unreadCount)") : nil) {
                        router.tab = .notifications
                    }
                    .accessibilityLabel("Bildirimler")
                }
            }
        }
        .frame(height: 44)

        MonthTitleBar(period: period, canGoNext: period < .current, onChange: change) {
            HStack(spacing: 6) {
                Text(eyebrow(receipts: receipts))
                if month.lock.locked {
                    HStack(spacing: 4) {
                        Icon(.lock, size: 12)
                        Text("KAPALI")
                    }
                    .foregroundStyle(FColor.warning)
                }
            }
            .fFont(11, .heavy, tracking: 0.4)
            .foregroundStyle(FColor.muted)
        }
        .padding(.top, 6)
    }

    private func eyebrow(receipts: [Receipt]) -> String {
        if isOffline, let at = month.updatedAt { return "FİŞLER · SON GÜNCELLEME \(TR.time(at))" }
        let uploading = uploads.items(for: period).filter { !$0.isDone }.count
        if uploading > 0 { return "FİŞLER · \(receipts.count + uploading) FİŞ" }
        if listLayout && !receipts.isEmpty { return "FİŞLER · \(receipts.count) FİŞ · \(TR.money(month.summary.totalAmount))" }
        return "FİŞLER"
    }

    // MARK: Content

    @ViewBuilder
    private func content(receipts: [Receipt], visible: [Receipt], dupes: Set<String>) -> some View {
        banners
        UploadProgressCard(period: period)

        if !listLayout {
            HStack(spacing: 8) {
                CreditsPill(credits: store.credits) { router.receiptsPath.append(.credits) }
                Spacer(minLength: 0)
                if !month.lock.locked {
                    Button { router.sheet = .submit } label: {
                        HStack(spacing: 6) {
                            Icon(.send, size: 14)
                            Text("Muhasebeciye gönder")
                        }
                        .fFont(12.5, .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(FColor.brand, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .fBrandShadow()
                    }
                    .buttonStyle(.plain)
                    .disabled(receipts.isEmpty)
                }
            }

            HStack(spacing: 8) {
                FStatTile(title: "FİŞ", value: "\(receipts.count)")
                FStatTile(title: "ANALİZ", value: "\(month.summary.analyzedCount)", suffix: "/\(receipts.count)")
                FStatTile(title: "İŞLENEN", value: "\(receipts.filter(\.processed).count)", suffix: "/\(receipts.count)")
            }
            TotalsCard(summary: month.summary)
        }

        filterBar(receipts: receipts)

        if listLayout {
            ForEach(visible.groupedForList(period: period), id: \.title) { group in
                HStack {
                    Text("\(group.title) · \(group.receipts.count) FİŞ").fFont(11.5, .heavy, tracking: 0.3)
                    Spacer()
                    Text(TR.money(group.receipts.totalAmount)).fFont(11.5, .bold).monospacedDigit()
                }
                .foregroundStyle(FColor.muted)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                FGroupedCard {
                    ForEach(Array(group.receipts.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowDivider() }
                        Button { router.receiptsPath.append(.receipt(id: r.id)) } label: { ReceiptRow(receipt: r) }
                            .buttonStyle(.plain)
                    }
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                UploadPlaceholderCards(period: period)
                ForEach(visible) { r in
                    Button { router.receiptsPath.append(.receipt(id: r.id)) } label: {
                        ReceiptCard(receipt: r, duplicate: dupes.contains(r.id), dimmed: month.lock.locked)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if visible.isEmpty && !receipts.isEmpty {
            Text("Bu filtrede fiş yok.")
                .fFont(13, .semibold).foregroundStyle(FColor.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if month.lock.locked {
            FBanner(icon: .lock, tone: .warning, text: Text("Bu ay muhasebecin tarafından ") + Text("kapatıldı").fontWeight(.heavy) + Text(" — mevcut fişlerde değişiklik yapılamaz; yeni fişler ilk açık aya eklenir."))
        }
        if let credits = store.credits, credits.exhausted, period == .current {
            Button { router.receiptsPath.append(.credits) } label: {
                FBanner(icon: .triangleAlert, tone: .warning, text: Text("Aylık analiz limitin doldu (\(credits.used)/\(credits.limit ?? credits.used)) — yeni fişler yüklenir ama sıraya alınır.")) {
                    Text("Limit →").fFont(12, .heavy).foregroundStyle(FColor.brand).fixedSize()
                }
            }
            .buttonStyle(.plain)
        }
        if let sent = month.submission?.lastSentAt {
            let processed = month.receipts.filter(\.processed).count
            let name = store.activeAccountant?.displayName
            let suffix = processed > 0 && name != nil ? " · \(name!) işledi (\(processed)/\(month.receipts.count))" : ""
            FBanner(icon: .circleCheck, tone: .success, text: Text("Gönderildi: \(TR.longDateTime(sent))\(suffix)"))
        }
    }

    private func filterBar(receipts: [Receipt]) -> some View {
        let unprocessed = receipts.filter { !$0.processed }.count
        let issues = receipts.filter { $0.openIssue != nil }.count
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FChip(title: "Tümü · \(receipts.count)", selected: filter == .all) { filter = .all }
                    FChip(title: unprocessed > 0 ? "İşlenmedi · \(unprocessed)" : "İşlenmedi", selected: filter == .unprocessed) { filter = .unprocessed }
                    FChip(title: "İşlendi", selected: filter == .processed) { filter = .processed }
                    FChip(title: issues > 0 ? "Sorunlu · \(issues)" : "Sorunlu", selected: filter == .issues) { filter = .issues }
                }
            }
            LayoutToggle(list: $listLayout)
        }
    }
}

/// Grid / list switch.
struct LayoutToggle: View {
    @Binding var list: Bool

    var body: some View {
        HStack(spacing: 2) {
            segment(.layoutGrid, active: !list) { list = false }
            segment(.list, active: list) { list = true }
        }
        .padding(2)
        .background(FColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FColor.lineStrong))
    }

    private func segment(_ icon: FIcon, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Icon(icon, size: 14)
                .foregroundStyle(active ? .white : FColor.muted)
                .frame(width: 28, height: 26)
                .background(active ? FColor.brand : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == .list ? "Liste görünümü" : "Kart görünümü")
    }
}

/// "● Bu ay 12/50 analiz"
struct CreditsPill: View {
    let credits: Credits?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
            }
            .fFont(11, .heavy)
            .foregroundStyle(credits?.exhausted == true ? FColor.warning : FColor.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FColor.lineStrong))
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        guard let credits else { return "Bu ay —" }
        if credits.unlimited { return "Bu ay \(credits.used) analiz · sınırsız" }
        return "Bu ay \(credits.used)/\(credits.limit ?? 0) analiz"
    }

    private var color: Color { credits?.exhausted == true ? FColor.warning : FColor.muted }
}

/// 2J
struct EmptyMonthView: View {
    let period: Period
    let previous: MonthState
    let onCamera: () -> Void
    let onGallery: () -> Void
    let onPrevious: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous).fill(FColor.brand.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(FColor.card)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(FColor.brand.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    .frame(width: 62, height: 78)
                    .rotationEffect(.degrees(-6))
                Icon(.camera, size: 20)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(FColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: FColor.brand.opacity(0.6), radius: 10, y: 8)
                    .offset(x: 24, y: 24)
            }
            .frame(width: 132, height: 132)

            VStack(spacing: 6) {
                Text("Bu ay henüz fiş yok").fFont(18, .heavy, tracking: -0.3)
                Text("Aldığın ilk fişin fotoğrafını çek, gerisini Fişlik halletsin. Tutar ve KDV otomatik okunur.")
                    .fFont(13.5, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 280)
            }

            HStack(spacing: 10) {
                Button(action: onCamera) { FButtonLabel(title: "Fiş Çek", icon: .camera) }
                    .buttonStyle(.f(.primary, height: 46, fontSize: 14))
                    .fixedSize()
                Button(action: onGallery) { FButtonLabel(title: "Galeriden Seç", icon: .images) }
                    .buttonStyle(.f(.secondary, height: 46, fontSize: 14))
                    .fixedSize()
            }

            if !previous.receipts.isEmpty {
                Button(action: onPrevious) {
                    HStack(spacing: 10) {
                        Icon(.chevronLeft, size: 16).foregroundStyle(FColor.muted)
                        (Text(period.previous.title).fontWeight(.heavy).foregroundColor(FColor.ink)
                         + Text(" · \(previous.receipts.count) fiş · \(TR.money(previous.summary.totalAmount))")
                         + (previous.submission?.lastSentAt != nil ? Text(" · ") + Text("Gönderildi").foregroundColor(FColor.success) : Text("")))
                            .fFont(12.5, .semibold)
                            .foregroundStyle(FColor.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .fCard(radius: 14)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

/// Dark "Çevrimdışı" pill (2AB).
struct OfflinePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Icon(.zapOff, size: 14)
            Text("Çevrimdışı")
        }
        .fFont(12.5, .bold)
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Color(hex: 0x0C1A18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

import SwiftUI

/// 2AF — one client's month: filters, multi-select, mark processed, export, close month.
struct ClientMonthView: View {
    let clientId: String
    let name: String

    @Environment(AccountantRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var notifications = NotificationsStore.shared
    @State private var uploads = UploadQueue.shared
    @State private var filter: Filter = .all
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var error: String?
    @State private var exporting = false
    @State private var dialog: Dialog?
    @State private var adding = false
    @State private var reportReceipt: Receipt?

    enum Filter { case all, unprocessed, issues, missing }
    enum Dialog { case lock, unlock }

    private var store: ReceiptStore { router.store(for: clientId) }
    private var period: Period { router.period }

    var body: some View {
        let month = store.state(period)
        let receipts = month.receipts
        let visible = receipts.filter(matches)
        let dupes = receipts.duplicateIds

        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 0) {
                            Icon(.chevronLeft, size: 22)
                            Text("Mükellefler").fFont(15, .bold)
                        }
                    }
                    Spacer()
                    if selecting {
                        Button("Vazgeç") { selecting = false; selected = [] }.fFont(15, .bold)
                    } else if !receipts.isEmpty {
                        Button("Seç") { selecting = true }.fFont(15, .bold)
                    }
                }
                .foregroundStyle(FColor.brand)
                .buttonStyle(.plain)
                .padding(.leading, 8).padding(.trailing, 16)
                .frame(height: 44)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).fFont(24, .heavy, tracking: -0.6).lineLimit(1)
                        Menu {
                            ForEach(0..<12, id: \.self) { i in
                                let p = Period.current.adding(-i)
                                Button(p.title) { router.period = p }
                            }
                        } label: {
                            subtitle(month: month)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        FIconButton(icon: .download, iconSize: 17) { exporting = true }
                            .accessibilityLabel("Dışa aktar")
                            .disabled(receipts.isEmpty)
                        FIconButton(icon: .lock, iconSize: 17, tint: month.lock.locked ? FColor.warning : FColor.muted) {
                            dialog = month.lock.locked ? .unlock : .lock
                        }
                        .accessibilityLabel(month.lock.locked ? "Ayı aç" : "Ayı kapat")
                    }
                }
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                FChip(title: "Tümü · \(receipts.count)", selected: filter == .all) { filter = .all }
                                FChip(title: "İşlenmedi · \(receipts.filter { !$0.processed }.count)", selected: filter == .unprocessed) { filter = .unprocessed }
                                FChip(title: "Sorunlu · \(receipts.filter { $0.openIssue != nil }.count)", selected: filter == .issues) { filter = .issues }
                                FChip(title: "Analiz eksik", selected: filter == .missing) { filter = .missing }
                            }
                        }
                        if month.lock.locked {
                            FBanner(icon: .lock, tone: .warning, text: Text("Bu ay kapatıldı\(month.lock.lockedAt.map { " · \(TR.longDay($0))" } ?? ""). Mükellef değişiklik yapamaz."))
                        }
                        if let error { FBanner(icon: .circleAlert, tone: .danger, text: Text(error)) }
                        UploadProgressCard(period: period)

                        if month.loaded && receipts.isEmpty {
                            Text("Bu ay fiş yok.").fFont(13, .semibold).foregroundStyle(FColor.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(visible) { r in
                                Button {
                                    if selecting { selected.toggle(r.id) }
                                    else { router.clientsPath.append(.receipt(id: r.id, clientId: clientId)) }
                                } label: {
                                    AccountantReceiptCard(receipt: r, duplicate: dupes.contains(r.id), selecting: selecting, selected: selected.contains(r.id))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(r.processed ? "İşlendi işaretini kaldır" : "İşlendi işaretle") { mark([r], !r.processed) }
                                    if r.openIssue == nil { Button("Sorun bildir") { reportReceipt = r } }
                                }
                                .onLongPressGesture { selecting = true; selected.insert(r.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await store.load(period, force: true) }

                bottomBar(receipts: receipts, visible: visible)
            }
            dialogs(month: month, receipts: receipts)
        }
        .animation(.easeOut(duration: 0.18), value: dialog)
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: period) { await store.load(period, force: true) }
        .onChange(of: uploads.activeCount) { old, new in
            if new < old { Task { await store.load(period, force: true) } }
        }
        .sheet(isPresented: $exporting) {
            ExportSheet(clientName: name, clientId: clientId, period: period, all: receipts, filtered: visible)
        }
        .sheet(isPresented: $adding) {
            AddReceiptSheet(clientId: clientId, periodOverride: period)
        }
        .sheet(item: $reportReceipt) { r in ReportIssueSheet(receipt: r, store: store) }
    }

    private func subtitle(month: MonthState) -> some View {
        let sent = notifications.items.first { $0.type == "receipts_submitted" && $0.payload["client_id"]?.string == clientId && $0.payload["period"]?.string == period.raw }
        return HStack(spacing: 0) {
            Text("\(period.title) · \(month.receipts.count) fiş · \(TR.money(month.summary.totalAmount))")
            if let sent {
                Text(" · ")
                Text("Gönderildi \(TR.shortDay(sent.createdAt))").fontWeight(.bold).foregroundStyle(FColor.success)
            }
            Icon(.chevronDown, size: 12).padding(.leading, 3)
        }
        .fFont(12, .semibold)
        .foregroundStyle(FColor.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func matches(_ r: Receipt) -> Bool {
        switch filter {
        case .all: true
        case .unprocessed: !r.processed
        case .issues: r.openIssue != nil
        case .missing: r.isQueued || r.isFailed || r.isPending
        }
    }

    @ViewBuilder
    private func bottomBar(receipts: [Receipt], visible: [Receipt]) -> some View {
        HStack(spacing: 8) {
            if selecting {
                Text("\(selected.count) seçildi").fFont(12.5, .bold).foregroundStyle(FColor.muted).fixedSize()
                let chosen = receipts.filter { selected.contains($0.id) }
                let allProcessed = !chosen.isEmpty && chosen.allSatisfy(\.processed)
                Button { mark(chosen, !allProcessed) } label: {
                    FButtonLabel(title: allProcessed ? "İşaretini kaldır" : "İşlendi işaretle", icon: .check, loading: busy)
                }
                .buttonStyle(.f(.primary, height: 44, fontSize: 14, radius: 13))
                .disabled(chosen.isEmpty || busy)
                Button { reportReceipt = chosen.first } label: {
                    Icon(.triangleAlert, size: 18).foregroundStyle(FColor.warning)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(FColor.lineStrong))
                }
                .buttonStyle(.plain)
                .disabled(chosen.count != 1 || chosen.first?.openIssue != nil)
                .accessibilityLabel("Sorun bildir")
            } else {
                Button { markAll(receipts) } label: {
                    FButtonLabel(title: receipts.allSatisfy(\.processed) && !receipts.isEmpty ? "Tümü işlendi" : "Tümünü işlendi işaretle", icon: .check, loading: busy)
                }
                .buttonStyle(.f(.primary, height: 44, fontSize: 14, radius: 13))
                .disabled(receipts.isEmpty || receipts.allSatisfy(\.processed) || busy)
                Button { adding = true } label: {
                    Icon(.camera, size: 18).foregroundStyle(FColor.brand)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(FColor.lineStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mükellef adına fiş yükle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(FColor.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(FColor.line).frame(height: 1) }
    }

    @ViewBuilder
    private func dialogs(month: MonthState, receipts: [Receipt]) -> some View {
        switch dialog {
        case .lock:
            FDialog(icon: .lock, title: "\(period.title)'yı kapat", confirmTitle: "Ayı kapat", confirmIcon: .lock, busy: busy, onCancel: { dialog = nil }, onConfirm: lock) {
                (Text(name).fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" bu ayda artık fiş ekleyemez, düzenleyemez veya silemez; yeni fişleri ilk açık aya düşer. İstediğin zaman tekrar açabilirsin."))
                    .dialogMessage()
                FGroupedCard {
                    summaryRow("İşlenen", "\(receipts.filter(\.processed).count) / \(receipts.count)", color: FColor.brand)
                    RowDivider()
                    summaryRow("Açık soru", "\(receipts.filter { $0.openIssue != nil }.count)")
                    RowDivider()
                    summaryRow("Toplam · KDV", "\(TR.money(month.summary.totalAmount)) · \(TR.money(month.summary.vatTotal))")
                }
                .background(FColor.bg)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(FColor.brand)
                    Text("Mükellefe bildirim gönderilir").fFont(13, .semibold).foregroundStyle(FColor.ink2)
                }
            }
        case .unlock:
            FDialog(icon: .lock, tint: FColor.warning, title: "\(period.title)'yı aç", confirmTitle: "Ayı aç", busy: busy, onCancel: { dialog = nil }, onConfirm: unlock) {
                (Text(name).fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" bu ayda yeniden fiş ekleyip düzenleyebilir."))
                    .dialogMessage()
            }
        case nil:
            EmptyView()
        }
    }

    private func summaryRow(_ label: String, _ value: String, color: Color = FColor.ink) -> some View {
        HStack {
            Text(label).fFont(12.5, .semibold).foregroundStyle(FColor.muted)
            Spacer()
            Text(value).fFont(13, .heavy).foregroundStyle(color).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    // MARK: Actions

    private func perform(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await work() } catch let e as APIError { error = e.message } catch {}
            await store.load(period, force: true)
        }
    }

    private func mark(_ receipts: [Receipt], _ processed: Bool) {
        perform {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for r in receipts { group.addTask { try await API.setProcessed(clientId: clientId, receiptId: r.id, processed) } }
                try await group.waitForAll()
            }
            selected = []
            selecting = false
        }
    }

    private func markAll(_ receipts: [Receipt]) {
        perform { _ = try await API.markMonthProcessed(clientId: clientId, period) }
    }

    private func lock() {
        perform {
            _ = try await API.lockPeriod(clientId: clientId, period)
            dialog = nil
        }
    }

    private func unlock() {
        perform {
            try await API.unlockPeriod(clientId: clientId, period)
            dialog = nil
        }
    }
}

/// Grid card with selection ring/checkbox for 2AF.
private struct AccountantReceiptCard: View {
    let receipt: Receipt
    let duplicate: Bool
    let selecting: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { ReceiptThumb(receipt: receipt, contentMode: receipt.isPDF ? .fill : .fit, alignment: receipt.isPDF ? .top : .center) }
                .clipped()
                .overlay(alignment: .topLeading) {
                    if selecting {
                        ZStack {
                            Circle().fill(selected ? FColor.brand : Color.white.opacity(0.9))
                            Circle().strokeBorder(selected ? .white : FColor.ink.opacity(0.25), lineWidth: 2)
                            if selected { Icon(.check, size: 13).foregroundStyle(.white) }
                        }
                        .frame(width: 24, height: 24)
                        .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge = badge { CardBadge(text: badge.0, color: badge.1).padding(7) }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text([TR.shortDay(receipt.displayDate), receipt.extraction?.paymentMethod?.label ?? (receipt.isFatura && receipt.extraction?.merchantTaxId == nil ? "VKN yok" : nil)].compactMap { $0 }.joined(separator: " · "))
                        .fFont(11, .semibold).foregroundStyle(FColor.muted)
                    Spacer()
                    if receipt.isFatura { FTag(text: "Fatura").fFont(9.5, .heavy) }
                }
                Text(receipt.merchant).fFont(13, .heavy).lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(TR.money(receipt.total)).fFont(14, .heavy).monospacedDigit()
                    Spacer(minLength: 0)
                    if let vat = receipt.vat { Text("KDV \(TR.money(vat))").fFont(10, .semibold).foregroundStyle(FColor.faint) }
                }
            }
            .foregroundStyle(FColor.ink)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
        }
        .background(FColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? FColor.brand : FColor.line, lineWidth: selected ? 2 : 1))
    }

    private var badge: (String, Color)? {
        if receipt.isWrongMonth { return ("Farklı ay", FColor.warning) }
        if duplicate { return ("Mükerrer?", FColor.warning) }
        if receipt.openIssue != nil { return ("Sorun var", FColor.warning) }
        if receipt.processed { return ("İşlendi", FColor.success) }
        if receipt.isQueued { return ("Sıraya alındı", FColor.muted) }
        return nil
    }
}

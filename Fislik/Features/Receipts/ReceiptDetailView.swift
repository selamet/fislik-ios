import SwiftUI

/// 2O / 2R — receipt detail. Works for the client (shared store) and for an accountant (client-scoped store).
struct ReceiptDetailView: View {
    let id: String
    var store: ReceiptStore = .shared

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String?
    @State private var dialog: Dialog?
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var fullscreen = false
    @State private var reporting = false
    @State private var rotation: Double = 0
    @State private var shareItem: ShareFile?

    enum Dialog { case delete, reanalyze }

    private var receiptId: String { currentId ?? id }

    var body: some View {
        Group {
            if let (receipt, period) = store.receipt(id: receiptId) {
                content(receipt, period: period)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fiş yükleniyor…").fFont(13, .semibold).foregroundStyle(FColor.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await locate() }
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Layout

    private func content(_ receipt: Receipt, period: Period) -> some View {
        let month = store.state(period)
        let list = month.receipts
        let index = list.firstIndex { $0.id == receipt.id } ?? 0
        let locked = month.lock.locked && !store.isAccountantMode
        let canEdit = store.isAccountantMode || (!locked && !receipt.processed)
        let canDelete = store.isAccountantMode ? receipt.uploadedBy == app.user?.id : (!locked && !receipt.processed)

        return ZStack {
            VStack(spacing: 0) {
                navBar(receipt, index: index, count: list.count)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(receipt, list: list, index: index)
                        titleBlock(receipt)
                        if let issue = receipt.openIssue {
                            IssueCard(issue: issue, isAccountant: store.isAccountantMode, onRetake: retake, onFix: { editing = true }, onResolve: { run { try await store.resolveIssue(receipt) } })
                        }
                        if let target = receipt.wrongMonthTarget, canEdit, let date = receipt.extraction?.receiptDate {
                            HStack(spacing: 8) {
                                Text("Fişin tarihi \(TR.dotted(date)) — bu fiş \(period.monthName) ayına yüklenmiş.")
                                    .fFont(12, .semibold)
                                Spacer(minLength: 4)
                                Button("\(target.monthName)'e taşı") { run { try await store.move(receipt, to: target) } }
                                    .fFont(12, .heavy).underline().foregroundStyle(FColor.warning).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(FColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.warning.opacity(0.35)))
                        }
                        if let error {
                            FBanner(icon: .circleAlert, tone: .danger, text: Text(error))
                        }
                        ReceiptFieldsCard(receipt: receipt, canEdit: canEdit, lockedReason: lockedReason(receipt, locked: locked), onEdit: { editing = true }, onReanalyze: {
                            if receipt.isFailed || receipt.isQueued { run { try await store.retry(receipt) } } else { dialog = .reanalyze }
                        })
                        if store.isAccountantMode {
                            accountantActions(receipt)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .refreshable { await store.load(period, force: true) }
                bottomBar(receipt, canDelete: canDelete)
            }
            dialogs(receipt)
        }
        .animation(.easeOut(duration: 0.18), value: dialog)
        .sheet(isPresented: $editing) {
            ReceiptEditView(receipt: receipt, store: store)
        }
        .sheet(isPresented: $reporting) {
            ReportIssueSheet(receipt: receipt, store: store)
        }
        .fullScreenCover(isPresented: $fullscreen) {
            ReceiptViewer(receipts: list.filter { !$0.isPDF || $0.id == receipt.id }, startId: receipt.id, initialRotation: rotation) { newId in
                currentId = newId
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func lockedReason(_ r: Receipt, locked: Bool) -> String? {
        if store.isAccountantMode { return nil }
        if locked { return "Ay kapalı — düzenleme yapılamaz" }
        if r.processed { return "İşlenmiş fişte düzenleme kapalı — muhasebecine yaz" }
        return nil
    }

    private func navBar(_ receipt: Receipt, index: Int, count: Int) -> some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 0) {
                    Icon(.chevronLeft, size: 22)
                    Text(store.isAccountantMode ? "Geri" : "Fişler").fFont(15, .bold)
                }
                .foregroundStyle(FColor.brand)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(index + 1) / \(count)").fFont(13, .heavy).foregroundStyle(FColor.muted).monospacedDigit()
            Spacer()
            HStack(spacing: 6) {
                FIconButton(icon: .share, iconSize: 17) { Task { await share(receipt) } }
                    .accessibilityLabel("Paylaş")
                Menu {
                    menuItems(receipt)
                } label: {
                    Icon(.ellipsis, size: 17)
                        .foregroundStyle(FColor.muted)
                        .frame(width: 38, height: 38)
                        .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                }
                .accessibilityLabel("Diğer")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private func menuItems(_ receipt: Receipt) -> some View {
        Button { fullscreen = true } label: { Label("Tam ekran", systemImage: "arrow.up.left.and.arrow.down.right") }
        if let current = Period(receipt.period) {
            Menu {
                ForEach(0..<6, id: \.self) { i in
                    let p = Period.current.adding(-i)
                    if p != current {
                        Button(p.title) { run { try await store.move(receipt, to: p) } }
                    }
                }
            } label: { Label("Başka aya taşı", systemImage: "calendar") }
        }
        Button { Task { await share(receipt) } } label: { Label("Görseli paylaş", systemImage: "square.and.arrow.up") }
    }

    private func header(_ receipt: Receipt, list: [Receipt], index: Int) -> some View {
        ZStack {
            Color(hex: 0x2A3937)
            if receipt.isPDF {
                // e-Fatura: show the top of the first page, as in 2R.
                ReceiptThumb(receipt: receipt, contentMode: .fill, showPaper: false, backdrop: .white, alignment: .top)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .padding(.top, 18).padding(.horizontal, 40)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: -10)
            } else {
                ReceiptThumb(receipt: receipt, contentMode: .fit, showPaper: true, backdrop: Color(hex: 0x2A3937))
                    .rotationEffect(.degrees(rotation))
                    .padding(.vertical, 10)
            }
        }
        .frame(height: receipt.isPDF ? 250 : 210)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { fullscreen = true }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if receipt.isPDF {
                    glassChip(icon: .fileText, title: "PDF") { fullscreen = true }
                } else {
                    glassChip(icon: .zoomIn, title: "Tam ekran") { fullscreen = true }
                    glassChip(icon: .rotateCw) { withAnimation { rotation += 90 } }
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if receipt.isPDF {
                glassChip(icon: .share, title: "Aç / Paylaş") { Task { await share(receipt) } }.padding(10)
            } else if let badge = receipt.badges(duplicate: false).first {
                CardBadge(text: badge.0, color: badge.1).padding(10)
            }
        }
        .overlay {
            if list.count > 1 && !receipt.isPDF {
                HStack {
                    pager(.chevronLeft, enabled: index > 0) { currentId = list[index - 1].id; rotation = 0 }
                    Spacer()
                    pager(.chevronRight, enabled: index < list.count - 1) { currentId = list[index + 1].id; rotation = 0 }
                }
                .padding(.horizontal, 8)
            }
        }
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.width < -50, index < list.count - 1 { currentId = list[index + 1].id; rotation = 0 }
            if v.translation.width > 50, index > 0 { currentId = list[index - 1].id; rotation = 0 }
        })
    }

    private func glassChip(icon: FIcon, title: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Icon(icon, size: 14)
                if let title { Text(title).fFont(11.5, .bold) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, title == nil ? 0 : 10)
            .frame(minWidth: 28, minHeight: 28)
            .background(Color(hex: 0x0C1A18).opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pager(_ icon: FIcon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 14).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color(hex: 0x0C1A18).opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    private func titleBlock(_ receipt: Receipt) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(receipt.merchant).fFont(22, .heavy, tracking: -0.5).lineLimit(2)
                    if let tag = receipt.docTag { FTag(text: tag).fFont(10, .heavy) }
                }
                Text(subtitle(receipt)).fFont(12, .semibold).foregroundStyle(FColor.muted)
            }
            Spacer(minLength: 0)
            if receipt.isPDF {
                FStatusBadge(text: receipt.status.label, color: receipt.status.color)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TR.money(receipt.total)).fFont(20, .heavy, tracking: -0.4).monospacedDigit()
                    if let vat = receipt.vat { Text("KDV \(TR.money(vat))").fFont(11, .semibold).foregroundStyle(FColor.faint) }
                }
            }
        }
    }

    private func subtitle(_ r: Receipt) -> String {
        var parts: [String] = []
        if let d = r.extraction?.receiptDate { parts.append(TR.longDay(d)) }
        if r.isPDF {
            parts.append(r.uploadedByAccountant ? "Muhasebeci yükledi" : "Dosyalar'dan yüklendi")
        } else {
            parts.append("Yüklendi \(TR.shortDateTime(r.createdAt))")
            parts.append(r.uploadedByAccountant ? "Muhasebeci yükledi" : "Fotoğraf")
        }
        return parts.joined(separator: " · ")
    }

    private func bottomBar(_ receipt: Receipt, canDelete: Bool) -> some View {
        HStack(spacing: 8) {
            Button { dialog = .delete } label: {
                HStack(spacing: 6) {
                    Icon(.trash, size: 14)
                    Text("Fişi sil")
                }
                .fFont(12.5, .bold)
                .foregroundStyle(FColor.danger)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.lineStrong))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.5)
            Spacer()
            Text(canDelete ? "Silinen fiş geri alınamaz" : receipt.processed ? "İşlenmiş fiş silinemez" : store.isAccountantMode ? "Yalnızca senin yüklediğin fişleri silebilirsin" : "Ay kapalı — fiş silinemez")
                .fFont(11, .semibold).foregroundStyle(FColor.faint).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(FColor.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(FColor.line).frame(height: 1) }
    }

    @ViewBuilder
    private func accountantActions(_ receipt: Receipt) -> some View {
        HStack(spacing: 8) {
            Button {
                run { try await store.setProcessed(receipt, !receipt.processed) }
            } label: {
                FButtonLabel(title: receipt.processed ? "İşlendi işaretini kaldır" : "İşlendi işaretle", icon: .check)
            }
            .buttonStyle(.f(receipt.processed ? .secondary : .primary, height: 46, fontSize: 14))
            if receipt.openIssue == nil {
                Button { reporting = true } label: { Icon(.triangleAlert, size: 18).foregroundStyle(FColor.warning) }
                    .frame(width: 46, height: 46)
                    .background(FColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.lineStrong))
                    .accessibilityLabel("Sorun bildir")
            }
        }
    }

    @ViewBuilder
    private func dialogs(_ receipt: Receipt) -> some View {
        switch dialog {
        case .delete:
            FDialog(icon: .trash, tint: FColor.danger, title: "Fişi sil", confirmTitle: "Evet, sil", confirmKind: .danger, busy: busy, onCancel: { dialog = nil }, onConfirm: {
                run(closeDialog: true) {
                    try await store.delete(receipt)
                    dismiss()
                }
            }) {
                (Text("\(receipt.merchant) · \(TR.money(receipt.total))").fontWeight(.heavy).foregroundColor(FColor.ink)
                 + Text(" kalıcı olarak silinsin mi? Muhasebecin bu fişi artık göremez ve ay toplamından düşer."))
                    .dialogMessage()
            }
        case .reanalyze:
            FDialog(icon: .rotateCw, title: "Yeniden analiz et", confirmTitle: "Analiz et", busy: busy, onCancel: { dialog = nil }, onConfirm: {
                run(closeDialog: true) { try await store.reanalyze(receipt) }
            }) {
                (Text("Bu fişi tekrar analiz etmek ") + Text("1 analiz kredisi").fontWeight(.heavy).foregroundColor(FColor.ink)
                 + Text(" harcar ve mevcut sonucun üzerine yazar.") + Text(receipt.extraction?.edited == true ? " Elle yaptığın düzeltme kaybolacak." : ""))
                    .dialogMessage()
                if let c = ReceiptStore.shared.credits, !c.unlimited, let limit = c.limit, let remaining = c.remaining {
                    HStack {
                        Text("Kalan kredi").fFont(12, .bold).foregroundStyle(FColor.muted)
                        Spacer()
                        (Text("\(remaining) / \(limit) ") + Text("→ \(max(remaining - 1, 0))").foregroundColor(FColor.muted).fontWeight(.semibold))
                            .fFont(13, .heavy)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(FColor.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        case nil:
            EmptyView()
        }
    }

    // MARK: Actions

    private func run(closeDialog: Bool = false, _ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer {
                busy = false
                if closeDialog { dialog = nil }
            }
            do { try await work() } catch let e as APIError { error = e.message } catch {}
        }
    }

    private func retake() {
        dismiss()
        app.pendingLink = .camera
    }

    private func share(_ receipt: Receipt) async {
        guard let data = await ReceiptImageLoader.shared.data(for: receipt) else { return }
        let ext = receipt.isPDF ? "pdf" : "jpg"
        let name = "\(receipt.merchant.slug)-\(receipt.extraction?.receiptDate.map(DateParsing.dayString) ?? receipt.period).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        shareItem = ShareFile(url: url)
    }

    /// Deep links may point at receipts outside loaded months.
    private func locate() async {
        for i in 0..<12 {
            await store.load(Period.current.adding(-i))
            if store.receipt(id: receiptId) != nil { return }
        }
    }
}

struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// "MUHASEBECİNİN SORUSU · ZEYNEP KAYA · 24 EKİ"
private struct IssueCard: View {
    let issue: ReceiptIssue
    let isAccountant: Bool
    let onRetake: () -> Void
    let onFix: () -> Void
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Icon(.triangleAlert, size: 13)
                Text(TR.upper("Muhasebecinin sorusu · \(issue.authorName ?? "Muhasebeci") · \(TR.shortDay(issue.createdAt))"))
            }
            .fFont(10.5, .heavy, tracking: 0.2)
            .foregroundStyle(FColor.warning)
            Text(issue.message).fFont(13, .semibold).lineSpacing(2)
            if !isAccountant {
                FlowLayout(spacing: 8) {
                    FMiniButton(title: "Yeniden çek", icon: .camera, height: 32, action: onRetake)
                    FMiniButton(title: issue.message.localizedCaseInsensitiveContains("vkn") ? "VKN'yi düzelt" : "Bilgileri düzelt", icon: .pencil, height: 32, action: onFix)
                    FMiniButton(title: "Çözüldü", icon: .check, color: FColor.success, height: 32, action: onResolve)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.warning.opacity(0.35)))
    }
}

/// "FİŞ BİLGİLERİ" table.
struct ReceiptFieldsCard: View {
    let receipt: Receipt
    let canEdit: Bool
    let lockedReason: String?
    let onEdit: () -> Void
    let onReanalyze: () -> Void

    var body: some View {
        let e = receipt.extraction
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Icon(.sparkles, size: 13).foregroundStyle(FColor.brand)
                    Text("FİŞ BİLGİLERİ")
                }
                .fFont(11, .heavy, tracking: 0.3)
                .foregroundStyle(FColor.muted)
                Spacer()
                if e?.edited == true {
                    FStatusBadge(text: "Elle doğrulandı", color: FColor.success, filled: true)
                } else if receipt.isPDF {
                    Text("PDF metninden okundu").fFont(11, .semibold).foregroundStyle(FColor.faint)
                } else if receipt.isPending {
                    Text("Analiz ediliyor…").fFont(11, .semibold).foregroundStyle(FColor.brand).modifier(Pulse())
                }
            }
            VStack(spacing: 7) {
                row("İşyeri", e?.merchantName)
                if let legal = e?.merchantLegalName { row("Ticari unvan", legal.displayCased) }
                row("VKN · Vergi dairesi", "\(e?.merchantTaxId ?? "—") · \(e?.merchantTaxOffice ?? "—")", warn: e?.merchantTaxId == nil && e?.docType == .fatura)
                row(receipt.isFatura ? "Fatura no" : "Fiş no", e?.receiptNumber, mono: true)
                row(receipt.isFatura ? "Fatura tarihi" : "Fiş tarihi", e?.receiptDate.map(TR.longDay), warn: receipt.isWrongMonth)
                row("Tür · Kategori · Ödeme", [e?.docType?.label, e?.expenseCategory?.label, e?.paymentMethod?.label].map { $0 ?? "—" }.joined(separator: " · "))
                row("Tutar", e?.totalAmount.map(TR.money), mono: true)
                HStack {
                    Text("KDV dökümü · \(TR.money(e?.vatTotal))").fFont(11.5, .bold).foregroundStyle(FColor.muted)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(e?.vatBreakdown ?? [], id: \.self) { VatChip(rate: $0.rate, amount: $0.amount) }
                    }
                }
            }
            .fFont(13, .bold)
            HStack(spacing: 8) {
                FMiniButton(title: "Düzelt", icon: .pencil, action: onEdit)
                    .disabled(!canEdit)
                    .opacity(canEdit ? 1 : 0.5)
                if let lockedReason {
                    Text(lockedReason).fFont(11, .semibold).foregroundStyle(FColor.faint)
                } else {
                    FMiniButton(title: receipt.isFailed || receipt.isQueued ? "Tekrar analiz et" : "Yeniden analiz et", icon: .rotateCw, action: onReanalyze)
                        .disabled(receipt.isPending)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fCard(radius: 16)
    }

    private func row(_ label: String, _ value: String?, warn: Bool = false, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).fFont(11.5, .bold).foregroundStyle(FColor.muted).fixedSize()
            Spacer(minLength: 0)
            Text(value ?? "—")
                .foregroundStyle(warn ? FColor.warning : FColor.ink)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

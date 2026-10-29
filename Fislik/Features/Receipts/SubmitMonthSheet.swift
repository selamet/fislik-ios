import SwiftUI

/// 2U — "Ekim fişlerini gönder".
struct SubmitMonthSheet: View {
    @Environment(ClientRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var store = ReceiptStore.shared
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    private var period: Period { router.period }

    var body: some View {
        let month = store.state(period)
        let receipts = month.receipts
        let analyzed = receipts.filter { $0.extraction?.status == .done }.count
        let issues = receipts.filter { $0.openIssue != nil }
        let wrong = receipts.filter(\.isWrongMonth)
        let accountant = store.activeAccountant
        let canSend = month.submission?.canSend ?? !receipts.isEmpty

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(period.monthName) fişlerini gönder").fFont(22, .heavy, tracking: -0.4)
                    Text("Muhasebecin bildirim alır ve ayı incelemeye başlar.").fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer()
                closeButton
            }

            if let accountant {
                HStack(spacing: 12) {
                    FAvatar(initials: accountant.displayName.initials, size: 46, radius: 15)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ALICI").fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                        Text(accountant.displayName).fFont(15, .heavy)
                        Text(accountant.displayEmail).fFont(12, .semibold).foregroundStyle(FColor.muted).lineLimit(1)
                    }
                    Spacer()
                    FStatusBadge(text: "Aktif", color: FColor.success)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .fCard(radius: 16)
            } else {
                FBanner(icon: .userPlus, tone: .warning, text: Text("Bağlı muhasebecin yok. Göndermek için önce muhasebecini davet et."))
            }

            HStack(spacing: 8) {
                FStatTile(title: "FİŞ", value: "\(receipts.count)")
                FStatTile(title: "TOPLAM", value: TR.moneyWhole(month.summary.totalAmount))
                FStatTile(title: "KDV", value: TR.money(month.summary.vatTotal))
            }
            .fFont(16, .heavy)

            FGroupedCard {
                checkRow(icon: analyzed == receipts.count ? .circleCheck : .clock,
                         color: analyzed == receipts.count ? FColor.success : FColor.warning,
                         text: analyzed == receipts.count ? Text("\(receipts.count) fişin tamamı analiz edildi") : Text("\(receipts.count - analyzed) fiş henüz analiz edilmedi"))
                if let first = issues.first {
                    RowDivider()
                    checkRow(icon: .triangleAlert, color: FColor.warning,
                             text: Text("\(issues.count) fişte açık soru var — ") + Text(first.merchant).fontWeight(.heavy),
                             action: ("Gör", { dismiss(); router.receiptsPath.append(.receipt(id: first.id)) }))
                }
                if let first = wrong.first, let target = first.wrongMonthTarget {
                    RowDivider()
                    checkRow(icon: .triangleAlert, color: FColor.warning,
                             text: Text("\(wrong.count) fiş farklı aya ait olabilir — ") + Text(first.merchant).fontWeight(.heavy),
                             action: ("Taşı", { Task { try? await store.move(first, to: target) } }))
                }
                if let last = lastSubmission {
                    RowDivider()
                    checkRow(icon: .clock, color: FColor.muted, text: Text("Son gönderim: \(last.0.title) · \(TR.dayMonth(last.1)), \(TR.time(last.1))"), muted: true)
                }
            }

            if let error { Text(error).fFont(12.5, .semibold).foregroundStyle(FColor.danger) }

            if accountant == nil {
                Button {
                    dismiss()
                    router.tab = .accountant
                    router.sheet = .inviteAccountant
                } label: { FButtonLabel(title: "Muhasebeci davet et", icon: .userPlus) }
                .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
            } else {
                Button(action: send) {
                    FButtonLabel(title: sent ? "Gönderildi" : canSend ? "Gönder · \(receipts.count) fiş" : "Bu ay zaten gönderildi", icon: sent ? .check : .send, loading: sending)
                }
                .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
                .disabled(!canSend || sending || sent || receipts.isEmpty)
            }
            Text("Bu ay yeni fiş eklersen tekrar gönderebilirsin.")
                .fFont(11.5, .semibold).foregroundStyle(FColor.muted).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(FColor.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task {
            await store.load(period, force: true)
            await store.refreshGrants()
            await store.load(period.previous)
        }
    }

    private var lastSubmission: (Period, Date)? {
        if let d = store.state(period).submission?.lastSentAt { return (period, d) }
        if let d = store.state(period.previous).submission?.lastSentAt { return (period.previous, d) }
        return nil
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Icon(.x, size: 16).foregroundStyle(FColor.muted)
                .frame(width: 32, height: 32)
                .background(FColor.ink.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kapat")
    }

    private func checkRow(icon: FIcon, color: Color, text: Text, action: (String, () -> Void)? = nil, muted: Bool = false) -> some View {
        HStack(spacing: 10) {
            Icon(icon, size: 17).foregroundStyle(color)
            text.fFont(13, .semibold).foregroundStyle(muted ? FColor.muted : FColor.ink)
            Spacer(minLength: 4)
            if let action {
                Button(action.0, action: action.1).fFont(12, .heavy).foregroundStyle(FColor.brand)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func send() {
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                try await store.submit(period)
                sent = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            } catch let e as APIError {
                error = e.message
            } catch {}
        }
    }
}

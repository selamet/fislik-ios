import SwiftUI

/// 2G grid card.
struct ReceiptCard: View {
    let receipt: Receipt
    var duplicate = false
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { ReceiptThumb(receipt: receipt, contentMode: receipt.isPDF ? .fill : .fit, alignment: receipt.isPDF ? .top : .center) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(receipt.badges(duplicate: duplicate).prefix(2).enumerated()), id: \.offset) { _, badge in
                            CardBadge(text: badge.0, color: badge.1)
                        }
                    }
                    .padding(7)
                }
                .overlay {
                    if receipt.isPending { AnalyzingOverlay() }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(dayLabel).fFont(11, .semibold).foregroundStyle(FColor.muted)
                    Spacer()
                    if receipt.isFatura { FTag(text: "Fatura").fFont(9.5, .heavy) }
                }
                footer
            }
            .foregroundStyle(FColor.ink)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(FColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FColor.line))
        .opacity(dimmed ? 0.92 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

extension ReceiptCard {
    private var dayLabel: String {
        Calendar.fislik.isDateInToday(receipt.createdAt) && receipt.extraction?.receiptDate == nil ? "Bugün" : TR.shortDay(receipt.displayDate)
    }

    /// 2M variants: analysing, queued (no credit), unreadable; otherwise merchant + totals.
    @ViewBuilder
    private var footer: some View {
        if receipt.isPending {
            HStack(spacing: 5) {
                Icon(.sparkles, size: 13)
                Text("Analiz ediliyor…")
            }
            .fFont(12, .bold)
            .foregroundStyle(FColor.brand)
            .modifier(Pulse())
            Text("Tutar ve KDV okunuyor").fFont(10, .semibold).foregroundStyle(FColor.faint)
        } else if receipt.isQueued {
            Text("Analiz limiti doldu").fFont(12, .bold).foregroundStyle(FColor.muted)
            Text("\(Period.current.renewalLabel)'da otomatik analiz").fFont(10, .semibold).foregroundStyle(FColor.faint)
        } else if receipt.isFailed && receipt.extraction?.merchantName == nil {
            HStack(spacing: 5) {
                Icon(.triangleAlert, size: 13)
                Text("Okunamadı")
            }
            .fFont(12, .bold)
            .foregroundStyle(FColor.warning)
            Text("Bilgileri elle gir →").fFont(10, .semibold).foregroundStyle(FColor.brand)
        } else {
            Text(receipt.merchant).fFont(13, .heavy).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TR.money(receipt.total)).fFont(14, .heavy).monospacedDigit().lineLimit(1).layoutPriority(1)
                Spacer(minLength: 0)
                if let vat = receipt.vat {
                    Text("KDV \(TR.money(vat))").fFont(10, .semibold).foregroundStyle(FColor.faint).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// fPulse keyframes: opacity 1 → .45 → 1 over 1.6s.
struct Pulse: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

/// White pill badge with colored dot that sits on thumbnails.
struct CardBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).fFont(10, .heavy)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(0.3)))
        .shadow(color: Color(hex: 0x0C1A18).opacity(0.14), radius: 3, y: 2)
    }
}

/// Shimmering band shown while the extraction is pending.
struct AnalyzingOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, FColor.brand.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: geo.size.height * 0.5)
                .offset(y: phase * geo.size.height)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = 1 }
                }
        }
        .allowsHitTesting(false)
    }
}

/// 2H list row.
struct ReceiptRow: View {
    let receipt: Receipt
    var showChevron = true
    var subtitleExtra: String?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if receipt.isPDF {
                    Icon(.fileText, size: 18).foregroundStyle(FColor.muted)
                        .frame(width: 44, height: 54)
                        .background(LinearGradient(colors: [Color(light: 0xEEF3F2, dark: 0x1A2524), Color(light: 0xDDE5E2, dark: 0x22302E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    ReceiptThumb(receipt: receipt, showPaper: false)
                        .frame(width: 44, height: 54)
                        .overlay { if receipt.isPending { AnalyzingOverlay() } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(receipt.merchant).fFont(14, .heavy).lineLimit(1)
                    if let tag = receipt.docTag {
                        FTag(text: tag).fFont(9, .heavy)
                    }
                }
                HStack(spacing: 6) {
                    Text(subtitleExtra ?? TR.shortDay(receipt.displayDate))
                    if let cat = receipt.categoryLabel {
                        Text("·")
                        Text(cat)
                    }
                    Text("·")
                    FStatusDot(text: receipt.status.label, color: receipt.status.color).fFont(11.5, .semibold)
                }
                .fFont(11.5, .semibold)
                .foregroundStyle(FColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(TR.money(receipt.total)).fFont(14, .heavy).monospacedDigit()
                if let vat = receipt.vat {
                    Text("KDV \(TR.money(vat))").fFont(10.5, .semibold).foregroundStyle(FColor.faint)
                }
            }
            .fixedSize()
            if showChevron {
                Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
            }
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Grouped card container used by list sections.
struct FGroupedCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(FColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FColor.line))
    }
}

struct RowDivider: View {
    var leading: CGFloat = 0
    var body: some View {
        Rectangle().fill(FColor.ink.opacity(0.06)).frame(height: 1).padding(.leading, leading)
    }
}

/// Month title block with prev/next segmented chevrons.
struct MonthTitleBar<Eyebrow: View>: View {
    let period: Period
    var canGoNext: Bool
    let onChange: (Period) -> Void
    @ViewBuilder var eyebrow: () -> Eyebrow

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow()
                Text(period.title)
                    .fFont(30, .heavy, tracking: -0.9)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 2) {
                chevron(.chevronLeft, enabled: true) { onChange(period.previous) }
                chevron(.chevronRight, enabled: canGoNext) { onChange(period.next) }
            }
            .padding(3)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
        }
    }

    private func chevron(_ icon: FIcon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 16)
                .foregroundStyle(FColor.muted)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(icon == .chevronLeft ? "Önceki ay" : "Sonraki ay")
    }
}

/// "TOPLAM ₺6.345,25 | TOPLAM KDV · ₺971,85 + rate chips" card.
struct TotalsCard: View {
    let summary: MonthSummary

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TOPLAM").fFont(10, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                Text(TR.money(summary.totalAmount)).fFont(22, .heavy, tracking: -0.5).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text("TOPLAM KDV · \(TR.money(summary.vatTotal))").fFont(10, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                HStack(spacing: 5) {
                    ForEach(rates, id: \.0) { rate, amount in
                        VatChip(rate: rate, amount: amount)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fCard(radius: 14)
    }

    private var rates: [(Int, Decimal)] {
        summary.vatByRate.compactMap { k, v in Int(k).map { ($0, v) } }
            .filter { $0.1 > 0 }
            .sorted { $0.0 > $1.0 }
            .prefix(3).map { $0 }
    }
}

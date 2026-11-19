import SwiftUI

/// "Raporlar": the active company's spending for one month. Managers see
/// the whole company, uploaders only their own receipts; the API decides
/// both that and whether the plan includes the detailed sections.
struct ReportsScreen: View {
    @Environment(ClientRouter.self) private var router
    @State private var companies = CompanyStore.shared
    @State private var period: Period
    @State private var report: MonthlyReport?
    @State private var error: APIError?
    @State private var loading = false

    init(period: Period = .current) {
        _period = State(initialValue: period)
    }

    private var canManagePlan: Bool { companies.active.map { $0.role != .uploader } ?? true }

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(back: "Fişler", title: "Raporlar")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MonthTitleBar(period: period, canGoNext: period < .current, onChange: { period = $0 }) {
                        Text(report?.isOwnScope == true ? "YALNIZCA SENİN FİŞLERİN" : "ŞİRKET HARCAMALARI")
                            .fFont(11, .heavy, tracking: 0.4)
                            .foregroundStyle(FColor.muted)
                    }
                    if let report, report.period == period.raw {
                        if report.isEmpty {
                            emptyState
                        } else {
                            ReportBody(report: report, canManagePlan: canManagePlan) {
                                router.receiptsPath.append(.plan)
                            }
                        }
                        // The company's own books: owners and admins only.
                        if !report.isOwnScope {
                            ManualExpensesSection(period: period) { await load() }
                        }
                    } else if let error {
                        LoadErrorView(error: error, retry: { Task { await load() } })
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: period) { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            FIconTile(icon: .chartColumn, size: 56, iconSize: 26)
            Text("Bu ay için rapor yok").fFont(17, .heavy)
            Text("\(period.title) döneminde yüklenmiş fiş bulunmuyor.")
                .fFont(13.5, .semibold)
                .foregroundStyle(FColor.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .accessibilityIdentifier("report-empty")
    }

    private func load() async {
        let requested = period
        loading = true
        defer { loading = false }
        do {
            let loaded = try await API.monthlyReport(requested)
            guard requested == period else { return }
            report = loaded
            error = nil
        } catch let failure as APIError {
            guard requested == period, !failure.isCancellation else { return }
            error = failure
        } catch {}
    }
}

struct ReportBody: View {
    let report: MonthlyReport
    let canManagePlan: Bool
    let openPlan: () -> Void

    var body: some View {
        let total = report.totals.totalAmount
        VStack(alignment: .leading, spacing: 12) {
            hero

            if report.detailed, !report.isOwnScope, !report.members.isEmpty {
                ReportSection(title: "Kişilere göre", hint: "Fişi yükleyen kişi") {
                    ForEach(report.members) { member in
                        ReportBarRow(
                            label: member.name,
                            detail: (member.isAccountant ? "Muhasebeci · " : "") + "\(member.receiptCount) fiş",
                            amount: member.totalAmount,
                            total: total
                        )
                    }
                }
                .accessibilityIdentifier("report-members")
            }

            if !report.categories.isEmpty {
                ReportSection(title: "Kategoriler") {
                    ForEach(report.categories) { line in
                        ReportBarRow(label: line.label, amount: line.amount, total: total)
                    }
                }
            }

            if !report.paymentMethods.isEmpty {
                ReportSection(title: "Ödeme yöntemi") {
                    ForEach(report.paymentMethods) { line in
                        ReportBarRow(label: line.label, amount: line.amount, total: total)
                    }
                }
            }

            if report.detailed {
                if !report.merchants.isEmpty {
                    ReportSection(title: "En çok harcama yapılan satıcılar") {
                        ForEach(report.merchants) { merchant in
                            ReportBarRow(label: merchant.label, detail: "\(merchant.receiptCount) fiş", amount: merchant.totalAmount, total: total)
                        }
                    }
                }
                if !report.trend.isEmpty {
                    ReportTrend(trend: report.trend, current: report.period)
                }
            } else {
                locked
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOPLAM HARCAMA").fFont(11, .heavy, tracking: 0.4).foregroundStyle(.white.opacity(0.75))
                Text(TR.money(report.totals.totalAmount)).fFont(32, .heavy, tracking: -1).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if let previous = report.previous {
                HStack(spacing: 6) {
                    if let change = report.changePercent {
                        Text(ReportMath.signedPercent(change))
                            .fFont(12, .heavy)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    Text("\(previous.title): \(TR.money(previous.totalAmount))").fFont(12, .semibold).opacity(0.85)
                }
            }
            HStack(spacing: 18) {
                heroStat("TOPLAM KDV", TR.money(report.totals.vatTotal))
                heroStat("FİŞ", "\(report.totals.receiptCount)")
            }
            if report.totals.hasManual, let manual = report.totals.manualAmount {
                Text("\(TR.money(manual)) elle girilen \(report.totals.manualCount ?? 0) giderden.")
                    .fFont(11.5, .semibold).opacity(0.85)
            }
            if report.totals.waitingCount > 0 {
                Text("\(report.totals.waitingCount) fiş henüz okunmadı, tutarlara dahil değil.")
                    .fFont(11.5, .semibold).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report-hero")
    }

    private func heroStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).fFont(10, .heavy, tracking: 0.4).opacity(0.75)
            Text(value).fFont(15, .heavy).monospacedDigit()
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 10) {
            FIconTile(icon: .lock, size: 38, iconSize: 17)
            Text("Ayrıntılı rapor Pro ve İşletme planlarında").fFont(15, .heavy)
            Text("Kimin ne kadar harcadığını, en çok alışveriş yapılan satıcıları, geçen aya göre değişimi ve son 6 ayın seyrini görmek için şirketinin planını yükselt.")
                .fFont(13, .semibold)
                .foregroundStyle(FColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if canManagePlan {
                Button("Planları gör", action: openPlan)
                    .buttonStyle(.fPrimary)
                    .accessibilityIdentifier("report-upgrade")
            } else {
                Text("Planı şirket sahibi ya da yöneticisi değiştirebilir.")
                    .fFont(11.5, .semibold)
                    .foregroundStyle(FColor.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FColor.brand.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .accessibilityIdentifier("report-locked")
    }
}

struct ReportSection<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fFont(15, .heavy, tracking: -0.2)
                Spacer()
                if let hint { Text(hint).fFont(11.5, .semibold).foregroundStyle(FColor.muted) }
            }
            content()
        }
        .foregroundStyle(FColor.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fCard(radius: 18)
    }
}

/// A labelled amount with a bar showing its share of the month's total.
struct ReportBarRow: View {
    let label: String
    var detail: String?
    let amount: Decimal
    let total: Decimal

    var body: some View {
        let fraction = ReportMath.share(amount, of: total)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text(label).font(FFont.jakarta(13.5, .bold))
                    + Text(detail.map { " · \($0)" } ?? "").font(FFont.jakarta(12.5, .semibold)).foregroundColor(FColor.muted))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(TR.money(amount)).fFont(13.5, .heavy).monospacedDigit()
                Text(ReportMath.percent(fraction)).fFont(11.5, .semibold).foregroundStyle(FColor.muted)
            }
            CreditBar(fraction: fraction, track: FColor.tint, fill: FColor.brand, height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monthly totals of the last periods as bars; the selected month is solid.
struct ReportTrend: View {
    let trend: [ReportPeriodTotals]
    let current: String

    var body: some View {
        let heights = ReportMath.heights(trend)
        ReportSection(title: "Son 6 ay", hint: "Aylık toplam") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(trend.enumerated()), id: \.element.id) { index, point in
                    VStack(spacing: 5) {
                        Text(point.totalAmount > 0 ? TR.moneyWhole(point.totalAmount) : " ")
                            .fFont(9.5, .bold)
                            .foregroundStyle(FColor.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(point.period == current ? FColor.brand : FColor.brand.opacity(0.25))
                            .frame(height: max(96 * heights[index], 3))
                        Text(point.shortMonth).fFont(11, .bold).foregroundStyle(FColor.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(point.title): \(TR.money(point.totalAmount))")
                }
            }
            .frame(height: 140, alignment: .bottom)
        }
        .accessibilityIdentifier("report-trend")
    }
}

/// Entry to the reports screen, shown under the month totals on the home screen.
struct ReportsRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FIconTile(icon: .chartColumn, size: 32, iconSize: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Harcama raporu").fFont(13.5, .heavy)
                    Text("Kişi, kategori ve satıcıya göre").fFont(11.5, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
            }
            .foregroundStyle(FColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .fCard(radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reports-row")
    }
}

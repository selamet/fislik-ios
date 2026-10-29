import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), data: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), data: context.isPreview ? .placeholder : (WidgetData.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let empty = WidgetData(period: Period.current.raw, count: 0, unprocessed: 0, total: 0, vat: 0, recent: [], updatedAt: Date())
        let entry = SnapshotEntry(date: Date(), data: WidgetData.load() ?? empty)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private extension WidgetData {
    /// Snapshot from a previous month: show zeros for the new month.
    var isStale: Bool { periodValue != .current }
}

private func toneColor(_ tone: String) -> Color {
    switch tone {
    case "success": FColor.success
    case "warning": FColor.warning
    default: FColor.muted
    }
}

// MARK: - Month (small + lock screen)

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let d = entry.data
        let count = d.isStale ? 0 : d.count
        let monthURL = URL(string: "fislik://ay/\(Period.current.raw)")
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(d.isStale ? 0 : d.unprocessed)").font(FFont.jakarta(22, .heavy))
                    Text("İŞLENMEDİ").font(FFont.jakarta(7, .bold))
                }
            }
            .widgetURL(monthURL)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TR.upper(Period.current.monthName)) · \(count) FİŞ").font(FFont.jakarta(10, .heavy)).opacity(0.75)
                Text(TR.money(d.isStale ? 0 : d.total)).font(FFont.jakarta(20, .heavy)).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(monthURL)
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(TR.upper(Period.current.monthName)).font(FFont.jakarta(10, .heavy)).tracking(0.4).foregroundStyle(FColor.muted)
                    Spacer()
                    FislikMark(height: 16)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(count)").font(FFont.jakarta(36, .heavy)).tracking(-1)
                    Text("fiş").font(FFont.jakarta(13, .bold)).foregroundStyle(FColor.muted)
                }
                Text("\(d.isStale ? 0 : d.unprocessed) işlenmedi · \(TR.moneyWhole(d.isStale ? 0 : d.total))")
                    .font(FFont.jakarta(11.5, .semibold)).foregroundStyle(FColor.muted).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Link(destination: URL(string: "fislik://kamera")!) {
                    HStack(spacing: 6) {
                        Icon(.camera, size: 15)
                        Text("Fiş Çek").font(FFont.jakarta(13, .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(FColor.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .foregroundStyle(FColor.ink)
            .widgetURL(monthURL)
        }
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FislikMonth", provider: SnapshotProvider()) { entry in
            MonthWidgetView(entry: entry).containerBackground(for: .widget) { FColor.card }
        }
        .configurationDisplayName("Bu ay")
        .description("Bu ayın fiş sayısı, toplamı ve hızlı fiş çekme.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Accountant question (small)

struct QuestionWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let q = entry.data.isStale ? nil : entry.data.question
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MUHASEBECİ").font(FFont.jakarta(10, .heavy)).tracking(0.4).foregroundStyle(FColor.muted)
                Spacer()
                Icon(q == nil ? .circleCheck : .triangleAlert, size: 12)
                    .foregroundStyle(q == nil ? FColor.success : FColor.warning)
                    .frame(width: 22, height: 22)
                    .background((q == nil ? FColor.success : FColor.warning).opacity(0.12), in: Circle())
            }
            Spacer(minLength: 4)
            if let q {
                (Text(q.accountant).fontWeight(.bold) + Text(" \(q.count) fiş için soru sordu").fontWeight(.semibold).foregroundColor(FColor.muted))
                    .font(FFont.jakarta(13, .bold))
                    .lineLimit(3)
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 18, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(FColor.ink.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(q.merchant).font(FFont.jakarta(11, .bold)).lineLimit(1)
                        Text(q.total).font(FFont.jakarta(11, .semibold)).foregroundStyle(FColor.muted)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 13).foregroundStyle(FColor.muted)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(FColor.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Açık soru yok").font(FFont.jakarta(13, .bold))
                Text("Muhasebecin bir şey sorarsa burada görünür.").font(FFont.jakarta(11, .semibold)).foregroundStyle(FColor.muted)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(FColor.ink)
        .widgetURL(q.flatMap { URL(string: "fislik://fis/\($0.receiptId)?period=\(entry.data.period)") } ?? URL(string: "fislik://bildirimler"))
    }
}

struct QuestionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FislikQuestion", provider: SnapshotProvider()) { entry in
            QuestionWidgetView(entry: entry).containerBackground(for: .widget) { FColor.card }
        }
        .configurationDisplayName("Muhasebeci")
        .description("Muhasebecinin fişlerin hakkındaki soruları.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Recent receipts (medium)

struct RecentWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let d = entry.data
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Period.current.upperTitle) · SON FİŞLER").font(FFont.jakarta(10, .heavy)).tracking(0.4).foregroundStyle(FColor.muted)
                Spacer()
                (Text(TR.money(d.isStale ? 0 : d.total)).font(FFont.jakarta(14, .heavy)) + Text(" · KDV \(TR.money(d.isStale ? 0 : d.vat))").font(FFont.jakarta(10, .bold)).foregroundColor(FColor.muted))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if d.isStale || d.recent.isEmpty {
                Spacer()
                Text("Bu ay henüz fiş yok").font(FFont.jakarta(13, .bold)).foregroundStyle(FColor.muted).frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(d.recent) { r in
                        Link(destination: URL(string: "fislik://fis/\(r.id)?period=\(d.period)")!) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 20, height: 26)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(FColor.ink.opacity(0.12)))
                                Text(r.merchant).font(FFont.jakarta(12, .bold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(r.day).font(FFont.jakarta(12, .semibold)).foregroundStyle(FColor.muted)
                                HStack(spacing: 4) {
                                    Circle().fill(toneColor(r.tone)).frame(width: 6, height: 6)
                                    Text(r.status).font(FFont.jakarta(10, .bold))
                                }
                                .foregroundStyle(toneColor(r.tone))
                                Text(r.total).font(FFont.jakarta(12, .heavy)).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                            }
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .top) { Rectangle().fill(FColor.ink.opacity(0.06)).frame(height: 1) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(FColor.ink)
        .widgetURL(URL(string: "fislik://ay/\(Period.current.raw)"))
    }
}

struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FislikRecent", provider: SnapshotProvider()) { entry in
            RecentWidgetView(entry: entry).containerBackground(for: .widget) { FColor.card }
        }
        .configurationDisplayName("Son fişler")
        .description("Bu ayın toplamı ve son yüklenen fişler.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Lock screen camera

struct CameraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FislikCamera", provider: SnapshotProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Icon(.camera, size: 26)
            }
            .widgetURL(URL(string: "fislik://kamera"))
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Fiş Çek")
        .description("Kilit ekranından tek dokunuşla fiş çek.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct FislikWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthWidget()
        QuestionWidget()
        RecentWidget()
        CameraWidget()
    }
}

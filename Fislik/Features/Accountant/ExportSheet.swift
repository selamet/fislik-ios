import SwiftUI

/// 2AG — export a client's month.
struct ExportSheet: View {
    let clientName: String
    let clientId: String
    let period: Period
    let all: [Receipt]
    let filtered: [Receipt]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportColumns") private var storedColumns = ExportColumn.defaults.map(\.rawValue).joined(separator: ",")
    @State private var format: ExportFormat = .excel
    @State private var onlyFiltered = false
    @State private var editingColumns = false
    @State private var working = false
    @State private var error: String?
    @State private var shareItem: ShareFile?

    private var columns: [ExportColumn] {
        let set = Set(storedColumns.split(separator: ",").map(String.init))
        return ExportColumn.allCases.filter { set.contains($0.rawValue) }
    }

    private var scope: [Receipt] { onlyFiltered ? filtered : all }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dışa aktar").fFont(22, .heavy, tracking: -0.4)
                    Text("\(clientName) · \(period.title) · \(all.count) fiş").fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Icon(.x, size: 16).foregroundStyle(FColor.muted)
                        .frame(width: 32, height: 32)
                        .background(FColor.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    formatTile(.excel, badge: "XLS", tint: FColor.success, title: "Excel", subtitle: "Sayı hücreleri")
                    formatTile(.csv, badge: "CSV", tint: FColor.muted, title: "CSV", subtitle: "Noktalı virgül")
                }
                GridRow {
                    formatTile(.pdf, badge: "PDF", tint: FColor.danger, title: "PDF döküm", subtitle: "Yazdırılabilir")
                    formatTile(.zip, badge: nil, tint: FColor.info, title: "ZIP", subtitle: "Tüm görseller")
                }
            }
            if format != .zip {
                VStack(spacing: 0) {
                    HStack {
                        Text("SÜTUNLAR · \(columns == ExportColumn.defaults ? "MUHASEBE VARSAYILANI" : "ÖZEL")").fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                        Spacer()
                        Button(editingColumns ? "Bitti" : "Düzenle") { withAnimation { editingColumns.toggle() } }.fFont(12, .bold).foregroundStyle(FColor.brand)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    RowDivider()
                    FlowLayout(spacing: 6) {
                        ForEach(editingColumns ? ExportColumn.allCases : columns) { c in
                            let on = columns.contains(c)
                            Button { toggle(c) } label: {
                                Text(c.rawValue)
                                    .fFont(11, .bold)
                                    .foregroundStyle(on ? FColor.brand : FColor.muted)
                                    .padding(.horizontal, 9)
                                    .frame(height: 26)
                                    .background(on ? FColor.brand.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? .clear : FColor.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(editingColumns)
                        }
                        if !editingColumns {
                            let hidden = ExportColumn.allCases.filter { !columns.contains($0) }
                            if !hidden.isEmpty {
                                Button { withAnimation { editingColumns = true } } label: {
                                    Text("+ " + hidden.map(\.rawValue).joined(separator: ", "))
                                        .fFont(11, .bold).foregroundStyle(FColor.muted)
                                        .padding(.horizontal, 9).frame(height: 26)
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FColor.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .fCard(radius: 16)

                HStack {
                    Text("Kapsam").fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                    Spacer()
                    FSegmented(options: [(false, "Tümü · \(all.count)"), (true, "Filtrelenen · \(filtered.count)")], selection: $onlyFiltered, height: 34).fixedSize()
                }
            }
            if let error { Text(error).fFont(12, .semibold).foregroundStyle(FColor.danger) }
            Button(action: export) {
                FButtonLabel(title: "Paylaş · \(Exporter.filename(client: clientName, period: period, format: format))", icon: .share, loading: working)
            }
            .buttonStyle(.f(.primary, height: 52, fontSize: 15, radius: 16))
            .disabled(working || scope.isEmpty || (format != .zip && columns.isEmpty))
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(FColor.bg.ignoresSafeArea())
        .fSelfSizingSheet()
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func formatTile(_ f: ExportFormat, badge: String?, tint: Color, title: String, subtitle: String) -> some View {
        Button { format = f } label: {
            HStack(spacing: 10) {
                Group {
                    if let badge { Text(badge).fFont(11, .heavy) } else { Icon(.package, size: 18) }
                }
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(tint == FColor.muted ? 0.08 : 0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).fFont(13.5, .heavy).foregroundStyle(FColor.ink)
                    Text(subtitle).fFont(11, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(format == f ? FColor.brand : FColor.ink.opacity(0.1), lineWidth: format == f ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ c: ExportColumn) {
        var set = Set(columns)
        if set.contains(c) { set.remove(c) } else { set.insert(c) }
        storedColumns = ExportColumn.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func export() {
        working = true
        error = nil
        let name = Exporter.filename(client: clientName, period: period, format: format)
        let rows = scope.sorted { $0.displayDate < $1.displayDate }
        let cols = columns
        Task {
            defer { working = false }
            do {
                let url: URL
                switch format {
                case .zip:
                    url = try await API.downloadZip(clientId: clientId, period, filename: name)
                case .excel, .csv, .pdf:
                    let data: Data = switch format {
                    case .excel: Exporter.xlsx(rows, columns: cols, sheetName: period.title)
                    case .csv: Exporter.csv(rows, columns: cols)
                    default: Exporter.pdf(rows, columns: cols, title: clientName, subtitle: "\(period.title) · \(rows.count) fiş · \(TR.money(rows.totalAmount))")
                    }
                    url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                }
                shareItem = ShareFile(url: url)
            } catch let e as APIError {
                error = e.status == 404 ? "Bu ay için görsel yok." : e.message
            } catch {
                self.error = "Dosya oluşturulamadı."
            }
        }
    }
}

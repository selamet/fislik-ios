import SwiftUI

/// "Ekstre karşılaştırma": upload a card or bank statement and see which of
/// its spending lines have no receipt. Owners and admins of paid-plan
/// companies; the API enforces both.
struct StatementsScreen: View {
    @State private var paid: Bool?
    @State private var statements: [Statement] = []
    @State private var selectedId: String?
    @State private var detail: Statement?
    @State private var loaded = false
    @State private var picking = false
    @State private var uploading = false
    @State private var message: String?
    @State private var deleting: Statement?
    @State private var booking: StatementLine?
    @State private var busyLine: String?
    @State private var onlyMissing = true

    private var currentId: String? { selectedId ?? statements.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(back: "Raporlar", title: "Ekstre karşılaştırma")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Kart ya da hesap ekstreni yükle; harcamalar fişlerinle ve elle girdiğin giderlerle karşılaştırılır, fişi eksik olanlar listelenir.")
                        .fFont(13, .semibold)
                        .foregroundStyle(FColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    uploadCard
                    if !statements.isEmpty { list }
                    if let detail, detail.id == currentId { detailView(detail) }
                    else if currentId != nil { ProgressView().frame(maxWidth: .infinity).padding(.top, 20) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .refreshable { await reload() }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            paid = (try? await API.billing())?.plan.isPaid
            await reload()
        }
        .task(id: currentId) { await loadDetail() }
        .confirmationDialog("Ekstre silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let deleting { remove(deleting) } }
        } message: {
            Text("\(deleting?.fileName ?? "") ve satırları silinir. Bu ekstreden eklediğin giderler silinmez.")
        }
        .sheet(item: $booking) { line in
            BookLineSheet(line: line) { category, description in
                try await act(on: line) {
                    try await API.expenseFromStatementLine(line.statementId(in: detail), line.id, category: category, description: description)
                }
                booking = nil
            }
        }
    }

    // MARK: Sections

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if paid == false {
                Text("Ekstre yükleme Pro ve İşletme planlarında. Planını yükselttiğinde buradan ekstre yükleyebilirsin.")
                    .fFont(13, .semibold)
                    .foregroundStyle(FColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("statement-plan-note")
            } else {
                Button { picking = true } label: {
                    FButtonLabel(title: uploading ? "Yükleniyor…" : "Ekstre yükle", icon: .download, loading: uploading)
                }
                .buttonStyle(.f(.primary, height: 48))
                .disabled(uploading || paid == nil)
                .accessibilityIdentifier("upload-statement")
                // On the button, not the screen: SwiftUI presents only one of
                // a file importer and a sheet attached to the same view.
                .fileImporter(isPresented: $picking, allowedContentTypes: StatementFiles.allowedTypes) { result in
                    if case .success(let url) = result { upload(url) }
                }
                Text("PDF, Excel (.xlsx) ya da CSV · en fazla 10 MB. Her ekstre aylık fiş limitinden \(StatementFiles.credits) hak kullanır (okunamazsa kullanmaz). Dosya yapay zekâ ile okunur ve saklanmaz; ekstreyi yalnızca şirket sahibi ve yöneticiler görür.")
                    .fFont(11.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                FBanner(icon: .circleAlert, tone: .danger, text: Text(message))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FColor.brand.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(statements) { statement in
                HStack(spacing: 8) {
                    Button { selectedId = statement.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statement.fileName).fFont(13.5, .bold).lineLimit(1)
                            Text(statement.summary)
                                .fFont(11.5, .semibold)
                                .foregroundStyle(statement.status == .failed ? FColor.danger : FColor.muted)
                                .lineLimit(2)
                        }
                        .foregroundStyle(FColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(currentId == statement.id ? FColor.brand.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statement-\(statement.id)")
                    Button { deleting = statement } label: {
                        Icon(.trash, size: 16).foregroundStyle(FColor.muted).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sil: \(statement.fileName)")
                }
            }
        }
        .padding(6)
        .fCard(radius: 18)
    }

    @ViewBuilder
    private func detailView(_ statement: Statement) -> some View {
        switch statement.status {
        case .processing:
            HStack(spacing: 10) {
                ProgressView()
                Text("\(statement.fileName) okunuyor; uzun ekstrelerde bir dakikayı bulabilir.")
                    .fFont(13, .semibold).foregroundStyle(FColor.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).fCard(radius: 18)
        case .failed:
            FBanner(icon: .circleAlert, tone: .danger,
                    text: Text("\(statement.fileName) okunamadı: \(statement.error ?? "bilinmeyen hata") Bu ekstre için hak kullanılmadı."))
        case .done:
            linesView(statement)
        }
    }

    private func linesView(_ statement: Statement) -> some View {
        let lines = statement.sortedLines.filter { !onlyMissing || $0.state == .missing }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statement.fileName).fFont(15, .heavy).lineLimit(1)
                Text(statement.missingCount == 0
                     ? "\(statement.lineCount) harcamanın hepsi karşılandı."
                     : "\(statement.lineCount) harcamadan \(statement.missingCount) tanesinin fişi eksik.")
                    .fFont(12, .semibold).foregroundStyle(FColor.muted)
            }
            Toggle(isOn: $onlyMissing) { Text("Yalnızca fişi eksik olanlar").fFont(13, .bold) }
                .toggleStyle(FToggleStyle())
                .accessibilityIdentifier("only-missing")
            if lines.isEmpty {
                Text(onlyMissing ? "Fişi eksik harcama kalmadı." : "Bu ekstrede harcama satırı yok.")
                    .fFont(12.5, .semibold).foregroundStyle(FColor.muted)
            }
            ForEach(lines) { line in lineRow(line) }
        }
        .foregroundStyle(FColor.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fCard(radius: 18)
    }

    private func lineRow(_ line: StatementLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.description).fFont(13.5, .bold).lineLimit(2)
                    Text([ExpenseDay.label(line.lineDate), line.matchLabel].compactMap { $0 }.joined(separator: " · "))
                        .fFont(11.5, .semibold).foregroundStyle(FColor.muted).lineLimit(2)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(TR.money(line.amount)).fFont(13.5, .heavy).monospacedDigit()
                    Text(line.stateLabel)
                        .fFont(10, .heavy)
                        .foregroundStyle(line.state == .missing ? FColor.warning : line.state == .ignored ? FColor.muted : FColor.brand)
                }
            }
            if line.state == .missing {
                HStack(spacing: 8) {
                    Button("Gider ekle") { booking = line }
                        .buttonStyle(.f(.primary, height: 36, fontSize: 13))
                        .accessibilityIdentifier("book-\(line.id)")
                    Button("Yok say") { ignore(line, true) }
                        .buttonStyle(.f(.secondary, height: 36, fontSize: 13))
                        .accessibilityIdentifier("ignore-\(line.id)")
                }
                .disabled(busyLine != nil)
            } else if line.state == .ignored {
                Button("Geri al") { ignore(line, false) }
                    .buttonStyle(.f(.secondary, height: 36, fontSize: 13))
                    .disabled(busyLine != nil)
                    .accessibilityIdentifier("restore-\(line.id)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func reload() async {
        do {
            statements = try await API.statements()
            loaded = true
            if let selectedId, !statements.contains(where: { $0.id == selectedId }) { self.selectedId = nil }
        } catch let error as APIError {
            if !error.isCancellation { message = StatementFiles.message(for: error) }
        } catch {}
    }

    /// Loads the selected statement, and keeps asking while it is being read.
    private func loadDetail() async {
        guard let id = currentId else { detail = nil; return }
        while !Task.isCancelled {
            guard let fresh = try? await API.statement(id) else { return }
            detail = fresh
            onlyMissing = fresh.missingCount > 0 && onlyMissing
            guard fresh.status == .processing else {
                if let i = statements.firstIndex(where: { $0.id == id }), statements[i].status != fresh.status {
                    await reload()
                }
                return
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func upload(_ url: URL) {
        message = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "Dosya açılamadı."
            return
        }
        guard data.count <= StatementFiles.maxBytes else {
            message = "Dosya çok büyük (en fazla 10 MB)."
            return
        }
        uploading = true
        Task {
            defer { uploading = false }
            do {
                let created = try await API.uploadStatement(fileName: url.lastPathComponent, data: data)
                statements.insert(created, at: 0)
                onlyMissing = true
                selectedId = created.id
            } catch let error as APIError {
                message = StatementFiles.message(for: error)
            } catch {}
        }
    }

    private func remove(_ statement: Statement) {
        Task {
            do {
                try await API.deleteStatement(statement.id)
                if selectedId == statement.id { selectedId = nil }
                detail = nil
                await reload()
            } catch let error as APIError {
                message = StatementFiles.message(for: error)
            } catch {}
        }
    }

    private func ignore(_ line: StatementLine, _ ignored: Bool) {
        Task {
            try? await act(on: line) {
                try await API.setStatementLineIgnored(line.statementId(in: detail), line.id, ignored: ignored)
            }
        }
    }

    /// Runs a line action and shows the statement it returns.
    private func act(on line: StatementLine, _ work: () async throws -> Statement) async throws {
        busyLine = line.id
        defer { busyLine = nil }
        do {
            let updated = try await work()
            detail = updated
            if let i = statements.firstIndex(where: { $0.id == updated.id }) {
                var summary = updated
                summary.lines = nil
                statements[i] = summary
            }
            message = nil
        } catch let error as APIError {
            message = StatementFiles.message(for: error)
            throw error
        }
    }
}

private extension StatementLine {
    func statementId(in detail: Statement?) -> String { detail?.id ?? "" }
}

/// Category and description for booking a statement line as a manual expense.
struct BookLineSheet: View {
    let line: StatementLine
    let submit: (_ category: String, _ description: String?) async throws -> Void

    @State private var category = "diger"
    @State private var text: String
    @State private var saving = false
    @State private var failure: String?

    init(line: StatementLine, submit: @escaping (_ category: String, _ description: String?) async throws -> Void) {
        self.line = line
        self.submit = submit
        _text = State(initialValue: line.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gider olarak ekle").fFont(22, .heavy, tracking: -0.5)
                Text("\(ExpenseDay.label(line.lineDate)) tarihli \(TR.money(line.amount)) tutarındaki harcama elle girilen giderlere eklenir ve raporda sayılır.")
                    .fFont(13, .medium).foregroundStyle(FColor.muted).fixedSize(horizontal: false, vertical: true)
            }
            FTextField(label: "Açıklama", text: $text)
            VStack(alignment: .leading, spacing: 6) {
                FFieldLabel(text: "Kategori")
                Menu {
                    ForEach(CategoryLabels.all, id: \.key) { option in Button(option.label) { category = option.key } }
                } label: {
                    HStack {
                        Text(CategoryLabels.label(category)).lineLimit(1)
                        Spacer(minLength: 4)
                        Icon(.chevronDown, size: 13).foregroundStyle(FColor.muted)
                    }
                    .fFont(14.5, .semibold)
                    .foregroundStyle(FColor.ink)
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .background(FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.fieldBorder))
                }
                .accessibilityIdentifier("book-category")
            }
            if let failure { FBanner(icon: .circleAlert, tone: .danger, text: Text(failure)) }
            Button {
                saving = true
                failure = nil
                Task {
                    defer { saving = false }
                    do {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        try await submit(category, trimmed.isEmpty ? nil : trimmed)
                    } catch let error as APIError {
                        failure = StatementFiles.message(for: error)
                    } catch {}
                }
            } label: {
                FButtonLabel(title: "Gider olarak ekle", loading: saving)
            }
            .buttonStyle(.f(.primary, height: 52))
            .disabled(saving)
            .accessibilityIdentifier("confirm-book")
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(FColor.card.ignoresSafeArea())
        .fSelfSizingSheet()
    }
}

/// Way into the statement screen from the reports screen.
struct StatementsRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FIconTile(icon: .fileText, size: 32, iconSize: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ekstre karşılaştırma").fFont(13.5, .heavy)
                    Text("Kart ya da hesap ekstreni yükle, fişi eksik harcamaları gör")
                        .fFont(11.5, .semibold).foregroundStyle(FColor.muted).lineLimit(2)
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
        .accessibilityIdentifier("statements-row")
    }
}

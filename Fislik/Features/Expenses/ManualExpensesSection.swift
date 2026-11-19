import SwiftUI

/// "Elle girilen giderler" of one month on the reports screen, for owners
/// and admins: spending without a receipt. `changed` reloads the report,
/// whose totals include these expenses.
struct ManualExpensesSection: View {
    let period: Period
    /// Bumped by the screen when expenses may have changed elsewhere
    /// (a new recurring rule can add this month's entry).
    var version = 0
    let changed: () async -> Void

    @State private var expenses: [Expense] = []
    @State private var loaded = false
    @State private var error: APIError?
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(Expense)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let expense): expense.id
            }
        }
    }

    var body: some View {
        ReportSection(title: "Elle girilen giderler", hint: "Fişi olmayan harcamalar") {
            if let error, !loaded {
                Text(error.message).fFont(12.5, .semibold).foregroundStyle(FColor.danger)
            } else if loaded && expenses.isEmpty {
                Text("\(period.title) için elle girilmiş gider yok. Kira, maaş, abonelik gibi kalemleri buradan ekleyebilirsin.")
                    .fFont(12.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(expenses) { expense in
                Button { editing = .existing(expense) } label: { row(expense) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expense-\(expense.id)")
            }
            Button { editing = .new } label: {
                HStack(spacing: 6) {
                    Icon(.plus, size: 15)
                    Text("Gider ekle")
                }
                .fFont(13.5, .heavy)
                .foregroundStyle(FColor.brand)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-expense")
        }
        .task(id: "\(period.raw)-\(version)") { await load() }
        .sheet(item: $editing) { target in
            ExpenseFormSheet(period: period, expense: {
                if case .existing(let expense) = target { return expense }
                return nil
            }()) {
                editing = nil
                Task {
                    await load()
                    await changed()
                }
            }
        }
    }

    private func row(_ expense: Expense) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(expense.description).fFont(13.5, .bold).lineLimit(1)
                    if expense.isRecurring {
                        Text("Tekrarlayan")
                            .fFont(10, .heavy)
                            .foregroundStyle(FColor.brand)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Text("\(expense.dateLabel) · \(CategoryLabels.label(expense.category))")
                    .fFont(11.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(TR.money(expense.amount)).fFont(13.5, .heavy).monospacedDigit()
            Icon(.chevronRight, size: 14).foregroundStyle(FColor.ink.opacity(0.3))
        }
        .foregroundStyle(FColor.ink)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func load() async {
        let requested = period
        do {
            let loadedExpenses = try await API.expenses(requested)
            guard requested == period else { return }
            expenses = loadedExpenses
            error = nil
            loaded = true
        } catch let failure as APIError {
            guard !failure.isCancellation else { return }
            error = failure
        } catch {}
    }
}

/// Add or edit a manual expense; editing also offers deleting it.
struct ExpenseFormSheet: View {
    let period: Period
    let expense: Expense?
    let done: () -> Void

    @State private var draft: ExpenseDraft
    @State private var errors = ExpenseDraft.Errors()
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmingDelete = false

    init(period: Period, expense: Expense?, done: @escaping () -> Void) {
        self.period = period
        self.expense = expense
        self.done = done
        _draft = State(initialValue: expense.map(ExpenseDraft.init) ?? ExpenseDraft(period: period))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense == nil ? "Gider ekle" : "Gideri düzenle").fFont(22, .heavy, tracking: -0.5)
                    Text("Fişi olmayan harcamalar için. Yalnızca şirket sahibi ve yöneticiler görür; muhasebeciye gönderilmez.")
                        .fFont(13, .medium)
                        .foregroundStyle(FColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FTextField(label: "Açıklama", text: $draft.description, placeholder: "Ofis kirası", error: errors.description)
                HStack(alignment: .top, spacing: 10) {
                    FTextField(label: "Tutar (TL)", text: $draft.amount, placeholder: "15.000,00", error: errors.amount, keyboard: .decimalPad)
                    FTextField(label: "İçindeki KDV", text: $draft.vat, placeholder: "İsteğe bağlı", error: errors.vat, keyboard: .decimalPad)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        FFieldLabel(text: "Tarih")
                        DatePicker("", selection: $draft.date, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, TR.locale)
                            .tint(FColor.brand)
                            .frame(height: 48)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FFieldLabel(text: "Kategori")
                        Menu {
                            ForEach(CategoryLabels.all, id: \.key) { option in
                                Button(option.label) { draft.category = option.key }
                            }
                        } label: {
                            HStack {
                                Text(CategoryLabels.label(draft.category)).lineLimit(1)
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
                        .accessibilityIdentifier("expense-category")
                    }
                }
                if let failure {
                    FBanner(icon: .circleAlert, tone: .danger, text: Text(failure))
                }
                Button(action: save) {
                    FButtonLabel(title: expense == nil ? "Gideri ekle" : "Kaydet", loading: saving)
                }
                .buttonStyle(.f(.primary, height: 52))
                .disabled(saving)
                .accessibilityIdentifier("save-expense")
                if expense != nil {
                    Button("Gideri sil") { confirmingDelete = true }
                        .fFont(14, .heavy)
                        .foregroundStyle(FColor.danger)
                        .frame(maxWidth: .infinity)
                        .disabled(saving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .background(FColor.card.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Gider silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive, action: remove)
        } message: {
            Text("\(draft.description) rapordan düşecek.")
        }
        .onChange(of: draft) { errors = ExpenseDraft.Errors() }
    }

    private func save() {
        switch draft.validated() {
        case .failure(let found):
            errors = found
        case .success(let body):
            run {
                if let expense { _ = try await API.updateExpense(expense.id, body) }
                else { _ = try await API.createExpense(body) }
            }
        }
    }

    private func remove() {
        guard let expense else { return }
        run { try await API.deleteExpense(expense.id) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        saving = true
        failure = nil
        Task {
            defer { saving = false }
            do {
                try await work()
                done()
            } catch let error as APIError {
                failure = error.message
            } catch {
                failure = APIError.transport(code: -1).message
            }
        }
    }
}

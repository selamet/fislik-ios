import SwiftUI

/// "Tekrarlayan giderler": monthly costs defined once. `paid` is whether the
/// plan includes them; on the free plan leftover rules are still listed so
/// they can be paused or removed, but nothing can be added or switched on.
struct RecurringExpensesSection: View {
    let paid: Bool
    /// Bumped by the screen when expenses may have changed elsewhere.
    let version: Int
    let changed: () async -> Void

    @State private var rules: [RecurringExpense] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: Target?
    @State private var toggling: String?

    enum Target: Identifiable {
        case new
        case existing(RecurringExpense)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let rule): rule.id
            }
        }
    }

    var body: some View {
        ReportSection(title: "Tekrarlayan giderler", hint: "Her ay kendiliğinden eklenir") {
            if !paid {
                Text("Tekrarlayan giderler Pro ve İşletme planlarında. Ücretsiz planda giderleri her ay elle ekleyebilirsin.")
                    .fFont(12.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recurring-plan-note")
            } else if loaded && rules.isEmpty {
                Text("Kira ya da abonelik gibi her ay aynı olan kalemleri bir kez tanımla; seçtiğin günde gider olarak eklensin.")
                    .fFont(12.5, .semibold)
                    .foregroundStyle(FColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).fFont(12.5, .semibold).foregroundStyle(FColor.danger)
            }
            ForEach(rules) { rule in row(rule) }
            if paid {
                Button { editing = .new } label: {
                    HStack(spacing: 6) {
                        Icon(.plus, size: 15)
                        Text("Tekrarlayan ekle")
                    }
                    .fFont(13.5, .heavy)
                    .foregroundStyle(FColor.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-recurring")
            }
        }
        .task(id: version) { await load() }
        .sheet(item: $editing) { target in
            RecurringFormSheet(rule: {
                if case .existing(let rule) = target { return rule }
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

    private func row(_ rule: RecurringExpense) -> some View {
        let note = rule.note(paid: paid)
        return HStack(spacing: 10) {
            Button { editing = .existing(rule) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.description).fFont(13.5, .bold).lineLimit(1)
                        Text([rule.schedule, CategoryLabels.label(rule.category), note].compactMap { $0 }.joined(separator: " · "))
                            .fFont(11.5, .semibold)
                            .foregroundStyle(FColor.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Text(TR.money(rule.amount)).fFont(13.5, .heavy).monospacedDigit()
                }
                .foregroundStyle(FColor.ink)
                .opacity(note == nil ? 1 : 0.6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recurring-\(rule.id)")
            Toggle("", isOn: Binding(get: { rule.active }, set: { toggle(rule, to: $0) }))
                .toggleStyle(FToggleStyle())
                .labelsHidden()
                .fixedSize()
                .disabled(toggling != nil || (!paid && !rule.active))
                .accessibilityLabel("Etkin: \(rule.description)")
        }
    }

    private func toggle(_ rule: RecurringExpense, to active: Bool) {
        toggling = rule.id
        Task {
            defer { toggling = nil }
            do {
                let updated = try await API.setRecurringExpenseActive(rule.id, active)
                if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = updated }
                error = nil
                await changed()
            } catch let failure as APIError {
                error = failure.message
            } catch {}
        }
    }

    private func load() async {
        do {
            rules = try await API.recurringExpenses()
            error = nil
            loaded = true
        } catch let failure as APIError {
            guard !failure.isCancellation else { return }
            error = failure.message
        } catch {}
    }
}

/// Add or edit a recurring rule; editing also offers deleting it.
struct RecurringFormSheet: View {
    let rule: RecurringExpense?
    let done: () -> Void

    @State private var draft: RecurringDraft
    @State private var errors = ExpenseDraft.Errors()
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmingDelete = false

    init(rule: RecurringExpense?, done: @escaping () -> Void) {
        self.rule = rule
        self.done = done
        _draft = State(initialValue: rule.map(RecurringDraft.init) ?? RecurringDraft())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule == nil ? "Tekrarlayan gider ekle" : "Tekrarlayan gideri düzenle").fFont(22, .heavy, tracking: -0.5)
                    Text(rule == nil
                         ? "Her ay seçtiğin günde kendiliğinden gider olarak eklenir. Günü bu ay geçtiyse bu ayın kaydı hemen oluşur."
                         : "Değişiklik bundan sonra oluşacak aylara uygulanır; önceki ayların kayıtları değişmez.")
                        .fFont(13, .medium)
                        .foregroundStyle(FColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FTextField(label: "Açıklama", text: $draft.description, placeholder: "Ofis kirası", error: errors.description)
                HStack(alignment: .top, spacing: 10) {
                    FTextField(label: "Aylık tutar (TL)", text: $draft.amount, placeholder: "15.000,00", error: errors.amount, keyboard: .decimalPad)
                    FTextField(label: "İçindeki KDV", text: $draft.vat, placeholder: "İsteğe bağlı", error: errors.vat, keyboard: .decimalPad)
                }
                HStack(alignment: .top, spacing: 10) {
                    picker("Ayın günü", value: "\(draft.day)", id: "recurring-day") {
                        ForEach(1...31, id: \.self) { day in Button("\(day)") { draft.day = day } }
                    }
                    picker("Kategori", value: CategoryLabels.label(draft.category), id: "recurring-category") {
                        ForEach(CategoryLabels.all, id: \.key) { option in Button(option.label) { draft.category = option.key } }
                    }
                }
                picker("Son ay (isteğe bağlı)", value: draft.endPeriod?.title ?? "Bitiş yok", id: "recurring-end") {
                    Button("Bitiş yok") { draft.endPeriod = nil }
                    ForEach(RecurringDraft.endChoices(), id: \.self) { period in Button(period.title) { draft.endPeriod = period } }
                }
                if let failure {
                    FBanner(icon: .circleAlert, tone: .danger, text: Text(failure))
                }
                Button(action: save) {
                    FButtonLabel(title: rule == nil ? "Ekle" : "Kaydet", loading: saving)
                }
                .buttonStyle(.f(.primary, height: 52))
                .disabled(saving)
                .accessibilityIdentifier("save-recurring")
                if rule != nil {
                    Button("Tekrarlayan gideri sil") { confirmingDelete = true }
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
        .confirmationDialog("Tekrarlayan gider silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive, action: remove)
        } message: {
            Text("Artık her ay eklenmeyecek. Önceki aylarda oluşan kayıtlar silinmez.")
        }
        .onChange(of: draft) { errors = ExpenseDraft.Errors() }
    }

    private func picker(_ label: String, value: String, id: String, @ViewBuilder items: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FFieldLabel(text: label)
            Menu { items() } label: {
                HStack {
                    Text(value).lineLimit(1)
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
            .accessibilityIdentifier(id)
        }
    }

    private func save() {
        switch draft.validated() {
        case .failure(let found):
            errors = found
        case .success(let body):
            run {
                if let rule { _ = try await API.updateRecurringExpense(rule.id, body) }
                else { _ = try await API.createRecurringExpense(body) }
            }
        }
    }

    private func remove() {
        guard let rule else { return }
        run { try await API.deleteRecurringExpense(rule.id) }
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

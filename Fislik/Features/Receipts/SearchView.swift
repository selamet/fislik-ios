import SwiftUI

/// Search + filter state; pure so it can be unit tested.
struct ReceiptQuery: Equatable {
    enum Range: Int, CaseIterable {
        case all = 12, thisMonth = 1, three = 3, six = 6

        var label: String {
            switch self {
            case .all: "Tüm aylar"
            case .thisMonth: "Bu ay"
            case .three: "Son 3 ay"
            case .six: "Son 6 ay"
            }
        }
    }

    var text = ""
    var status: ReceiptFilter = .all
    var docTypes: Set<DocType> = []
    var categories: Set<ExpenseCategory> = []
    var minAmount = ""
    var maxAmount = ""
    var range: Range = .all

    var isEmpty: Bool { self == ReceiptQuery() }
    var hasFilters: Bool {
        var copy = self
        copy.text = ""
        return copy != ReceiptQuery()
    }

    func matches(_ r: Receipt, period: Period, now: Period = .current) -> Bool {
        if period < now.adding(-(range.rawValue - 1)) { return false }
        if !r.matches(status) { return false }
        if !docTypes.isEmpty && !docTypes.contains(r.extraction?.docType ?? .unknown) { return false }
        if !categories.isEmpty && !categories.contains(r.extraction?.expenseCategory ?? .diger) { return false }
        if let min = TR.parseMoney(minAmount), (r.total ?? 0) < min { return false }
        if let max = TR.parseMoney(maxAmount), (r.total ?? 0) > max { return false }
        let q = text.trimmingCharacters(in: .whitespaces).lowercased(with: TR.locale)
        guard !q.isEmpty else { return true }
        let e = r.extraction
        let haystack = [e?.merchantName, e?.merchantLegalName, e?.receiptNumber, e?.merchantTaxId, e?.merchantTaxOffice, e?.expenseCategory?.label]
            .compactMap { $0?.lowercased(with: TR.locale) }
        return haystack.contains { $0.contains(q) }
    }
}

/// 2I — search across months.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientRouter.self) private var router
    @State private var store = ReceiptStore.shared
    @State private var query = ReceiptQuery()
    @State private var showAllCategories = false
    @FocusState private var focused: Bool

    private static let primaryCategories: [ExpenseCategory] = [.market, .yakit, .yemek]

    var body: some View {
        let results = store.allLoaded.filter { query.matches($0.1, period: $0.0) }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Icon(.search, size: 16).foregroundStyle(FColor.muted)
                    TextField("Satıcı, fiş no, VKN…", text: $query.text)
                        .fFont(15, .medium)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.text.isEmpty {
                        Button { query.text = "" } label: { Icon(.x, size: 15).foregroundStyle(Color(hex: 0x9AA6A4)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? FColor.brand : FColor.lineStrong))
                Button("Vazgeç") { dismiss() }.fFont(15, .bold).foregroundStyle(FColor.brand)
            }
            .frame(height: 44)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !query.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SONUÇLAR · \(query.range == .all ? "TÜM AYLAR" : TR.upper(query.range.label)) · \(results.count)")
                                .fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                            if results.isEmpty {
                                Text("Eşleşen fiş bulunamadı.").fFont(13, .semibold).foregroundStyle(FColor.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 24).fCard()
                            } else {
                                FGroupedCard {
                                    ForEach(Array(results.prefix(100).enumerated()), id: \.element.1.id) { i, item in
                                        if i > 0 { RowDivider() }
                                        Button {
                                            router.receiptsPath.append(.receipt(id: item.1.id))
                                        } label: {
                                            SearchResultRow(receipt: item.1, period: item.0, query: query.text)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    filters
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .task { await loadHistory() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FİLTRELER").fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                Spacer()
                if query.hasFilters {
                    Button("Temizle") {
                        let text = query.text
                        query = ReceiptQuery()
                        query.text = text
                    }
                    .fFont(12, .bold).foregroundStyle(FColor.brand)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                group("Durum") {
                    FChip(title: "Tümü", selected: query.status == .all) { query.status = .all }
                    FChip(title: "İşlenmedi", selected: query.status == .unprocessed) { query.status = .unprocessed }
                    FChip(title: "İşlendi", selected: query.status == .processed) { query.status = .processed }
                    FChip(title: "Sorunlu", selected: query.status == .issues) { query.status = .issues }
                }
                group("Belge türü · Kategori") {
                    ForEach([DocType.fis, .fatura], id: \.self) { t in
                        FChip(title: t.label, selected: query.docTypes.contains(t), outlinedSelection: true) { query.docTypes.toggle(t) }
                    }
                    let categories = showAllCategories ? ExpenseCategory.allCases : Self.primaryCategories
                    ForEach(categories, id: \.self) { c in
                        FChip(title: c.label, selected: query.categories.contains(c), outlinedSelection: true) { query.categories.toggle(c) }
                    }
                    if !showAllCategories {
                        FChip(title: "+\(ExpenseCategory.allCases.count - Self.primaryCategories.count)") { withAnimation { showAllCategories = true } }
                    }
                }
                Grid(horizontalSpacing: 8) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tutar").fFont(11.5, .bold).foregroundStyle(FColor.muted)
                            HStack(spacing: 4) {
                                TextField("Min", text: $query.minAmount).keyboardType(.decimalPad)
                                Text("—").foregroundStyle(FColor.muted)
                                TextField("Max", text: $query.maxAmount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                            .fFont(13, .medium)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(FColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FColor.fieldBorder))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tarih").fFont(11.5, .bold).foregroundStyle(FColor.muted)
                            Menu {
                                ForEach(ReceiptQuery.Range.allCases, id: \.self) { r in
                                    Button(r.label) { query.range = r }
                                }
                            } label: {
                                HStack {
                                    Text(query.range.label).foregroundStyle(query.range == .all ? FColor.muted : FColor.ink)
                                    Spacer()
                                    Icon(.chevronDown, size: 14).foregroundStyle(FColor.muted)
                                }
                                .fFont(13, .medium)
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                                .background(FColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FColor.fieldBorder))
                            }
                        }
                    }
                }
            }
            .padding(12)
            .fCard(radius: 16)
        }
    }

    private func group(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fFont(11.5, .bold).foregroundStyle(FColor.muted)
            FlowLayout { chips() }
        }
    }

    /// Fetch the last 12 months so search covers "tüm aylar".
    private func loadHistory() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<12 {
                let p = Period.current.adding(-i)
                group.addTask { await store.load(p) }
            }
        }
    }
}

struct SearchResultRow: View {
    let receipt: Receipt
    let period: Period
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumb(receipt: receipt, showPaper: false)
                .frame(width: 36, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                highlighted(receipt.merchant).fFont(14, .heavy)
                Text([TR.shortDay(receipt.displayDate), period.title, receipt.categoryLabel].compactMap { $0 }.joined(separator: " · "))
                    .fFont(11.5, .semibold).foregroundStyle(FColor.muted)
            }
            Spacer()
            Text(TR.money(receipt.total)).fFont(14, .heavy).monospacedDigit()
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Marks the matched substring with a teal highlight.
    private func highlighted(_ text: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: TR.locale) else { return Text(text) }
        var attributed = AttributedString(text)
        if let r = Range(range, in: attributed) {
            attributed[r].backgroundColor = FColor.brand.opacity(0.18)
        }
        return Text(attributed)
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

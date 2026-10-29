import SwiftUI

/// Editable copy of an extraction.
struct ExtractionDraft: Equatable {
    struct VatRow: Equatable, Identifiable {
        let id = UUID()
        var rate: Int
        var amount: String
    }

    var merchantName = ""
    var legalName = ""
    var docType: DocType = .fis
    var taxId = ""
    var taxOffice = ""
    var date: Date?
    var receiptNumber = ""
    var total = ""
    var vatTotal = ""
    var vatRows: [VatRow] = []
    var category: ExpenseCategory?
    var payment: PaymentMethod?

    static let rates = [20, 10, 1, 0, 8, 18]

    init(_ e: Extraction?) {
        guard let e else { return }
        merchantName = e.merchantName ?? ""
        legalName = e.merchantLegalName ?? ""
        docType = e.docType == .fatura ? .fatura : .fis
        taxId = e.merchantTaxId ?? ""
        taxOffice = e.merchantTaxOffice ?? ""
        date = e.receiptDate
        receiptNumber = e.receiptNumber ?? ""
        total = e.totalAmount.map(TR.plain) ?? ""
        vatTotal = e.vatTotal.map(TR.plain) ?? ""
        vatRows = e.vatBreakdown.map { VatRow(rate: $0.rate, amount: TR.plain($0.amount)) }
        category = e.expenseCategory
        payment = e.paymentMethod
    }

    /// Sends every field so the server marks the extraction as manually verified.
    var patch: ExtractionPatch {
        var p = ExtractionPatch()
        p.merchantName = .some(merchantName.nilIfBlank)
        p.merchantLegalName = .some(legalName.nilIfBlank)
        p.docType = .some(docType)
        let digits = taxId.filter(\.isNumber)
        p.merchantTaxId = .some(digits.nilIfBlank)
        p.merchantTaxIdType = .some(digits.count == 11 ? .tckn : digits.count == 10 ? .vkn : nil)
        p.merchantTaxOffice = .some(taxOffice.nilIfBlank)
        p.receiptDate = .some(date.map(DateParsing.dayString))
        p.receiptNumber = .some(receiptNumber.nilIfBlank)
        p.totalAmount = .some(TR.parseMoney(total))
        p.vatTotal = .some(TR.parseMoney(vatTotal) ?? vatSum)
        p.vatBreakdown = vatRows.compactMap { row in TR.parseMoney(row.amount).map { VatLine(rate: row.rate, amount: $0) } }
        p.expenseCategory = .some(category)
        p.paymentMethod = .some(payment)
        return p
    }

    var vatSum: Decimal? {
        let values = vatRows.compactMap { TR.parseMoney($0.amount) }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var taxIdError: String? {
        let n = taxId.filter(\.isNumber).count
        return n == 0 || n == 10 || n == 11 ? nil : "VKN 10, TCKN 11 haneli olmalı"
    }
}

/// 2P — "Düzelt" sheet.
struct ReceiptEditView: View {
    let receipt: Receipt
    let store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExtractionDraft
    @State private var original: ExtractionDraft
    @State private var saving = false
    @State private var error: String?
    @State private var showImage = false

    init(receipt: Receipt, store: ReceiptStore) {
        self.receipt = receipt
        self.store = store
        let d = ExtractionDraft(receipt.extraction)
        _draft = State(initialValue: d)
        _original = State(initialValue: d)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Vazgeç") { dismiss() }.fFont(15, .bold).foregroundStyle(FColor.brand)
                Spacer()
                Text("Düzelt").fFont(15, .heavy)
                Spacer()
                Button {
                    save()
                } label: {
                    if saving { ProgressView() } else { Text("Kaydet").fFont(15, .heavy) }
                }
                .foregroundStyle(FColor.brand)
                .disabled(saving || draft.taxIdError != nil)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 10) {
                    Button { showImage = true } label: {
                        HStack(spacing: 10) {
                            ReceiptThumb(receipt: receipt, showPaper: false)
                                .frame(width: 48, height: 60)
                                .background(Color(hex: 0x2A3937))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            (Text("Fotoğrafla karşılaştırarak düzelt. Kaydedince ") + Text("Elle doğrulandı").fontWeight(.heavy).foregroundColor(FColor.success) + Text(" etiketi eklenir."))
                                .fFont(12, .semibold).foregroundStyle(FColor.muted).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Icon(.zoomIn, size: 16).foregroundStyle(FColor.brand)
                        }
                        .padding(10)
                        .fCard(radius: 14)
                    }
                    .buttonStyle(.plain)

                    if let error { FBanner(icon: .circleAlert, tone: .danger, text: Text(error)) }

                    VStack(spacing: 10) {
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow {
                                EditField(label: "İşyeri", text: $draft.merchantName)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Tür").fFont(11.5, .bold).foregroundStyle(FColor.muted)
                                    FSegmented(options: [(DocType.fis, "Fiş"), (DocType.fatura, "Fatura")], selection: $draft.docType, height: 42)
                                }
                            }
                        }
                        EditField(label: "Ticari unvan", text: $draft.legalName)
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow {
                                EditField(label: "VKN / TCKN", text: $draft.taxId, keyboard: .numberPad, error: draft.taxIdError)
                                    .gridCellColumns(1)
                                EditField(label: "Vergi dairesi", text: $draft.taxOffice)
                            }
                            GridRow {
                                EditDateField(label: draft.docType == .fatura ? "Fatura tarihi" : "Fiş tarihi", date: $draft.date)
                                EditField(label: draft.docType == .fatura ? "Fatura no" : "Fiş no", text: $draft.receiptNumber, fontSize: 13)
                            }
                            GridRow {
                                EditField(label: "Toplam tutar", text: $draft.total, keyboard: .decimalPad, trailing: true, bold: true)
                                EditField(label: "Toplam KDV", text: $draft.vatTotal, keyboard: .decimalPad, trailing: true, bold: true)
                            }
                        }
                        vatEditor
                        Grid(horizontalSpacing: 10) {
                            GridRow {
                                pickerField("Kategori", value: draft.category?.label) {
                                    ForEach(ExpenseCategory.allCases, id: \.self) { c in Button(c.label) { draft.category = c } }
                                }
                                pickerField("Ödeme", value: draft.payment?.label) {
                                    ForEach(PaymentMethod.allCases, id: \.self) { p in Button(p.label) { draft.payment = p } }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .fCard(radius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FColor.bg.ignoresSafeArea())
        .interactiveDismissDisabled(draft != original)
        .fullScreenCover(isPresented: $showImage) {
            ReceiptViewer(receipts: [receipt], startId: receipt.id)
        }
    }

    private var vatEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KDV dökümü").fFont(11.5, .bold).foregroundStyle(FColor.muted)
            ForEach($draft.vatRows) { $row in
                HStack(spacing: 6) {
                    Menu {
                        ForEach(ExtractionDraft.rates, id: \.self) { r in Button("%\(r)") { row.rate = r } }
                    } label: {
                        HStack {
                            Text("%\(row.rate)")
                            Spacer()
                            Icon(.chevronDown, size: 13)
                        }
                        .fFont(13, .bold)
                        .foregroundStyle(FColor.ink)
                        .padding(.horizontal, 8)
                        .frame(width: 72, height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                    }
                    TextField("0,00", text: $row.amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .fFont(13, .bold)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                    Button { draft.vatRows.removeAll { $0.id == row.id } } label: {
                        Icon(.x, size: 13).foregroundStyle(FColor.muted)
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let used = Set(draft.vatRows.map(\.rate))
                draft.vatRows.append(.init(rate: ExtractionDraft.rates.first { !used.contains($0) } ?? 20, amount: ""))
            } label: {
                HStack(spacing: 4) {
                    Icon(.plus, size: 12)
                    Text("Satır ekle")
                }
                .fFont(11.5, .bold)
                .foregroundStyle(FColor.muted)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(FColor.lineStrong))
            }
            .buttonStyle(.plain)
        }
    }

    private func pickerField(_ label: String, value: String?, @ViewBuilder items: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).fFont(11.5, .bold).foregroundStyle(FColor.muted)
            Menu { items() } label: {
                HStack {
                    Text(value ?? "Seç").foregroundStyle(value == nil ? FColor.muted : FColor.ink)
                    Spacer()
                    Icon(.chevronDown, size: 13).foregroundStyle(FColor.muted)
                }
                .fFont(14, .semibold)
                .padding(.horizontal, 11)
                .frame(height: 42)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
            }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await store.patch(receipt, draft.patch)
                dismiss()
            } catch let e as APIError {
                error = e.message
            } catch {}
        }
    }
}

/// Compact 42pt field used in the edit form.
private struct EditField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var trailing = false
    var bold = false
    var fontSize: CGFloat = 14
    var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).fFont(11.5, .bold).foregroundStyle(FColor.muted)
            TextField("", text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .fFont(bold ? 15 : fontSize, bold ? .heavy : .semibold)
                .monospacedDigit()
                .focused($focused)
                .padding(.horizontal, 11)
                .frame(height: 42)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(error != nil ? FColor.danger : focused ? FColor.brand : FColor.ink.opacity(0.1), lineWidth: focused ? 1.5 : 1))
            if let error { Text(error).fFont(10.5, .semibold).foregroundStyle(FColor.danger) }
        }
    }
}

/// "22.10.2026 📅" field in the edit form's 42pt style; opens a graphical picker.
private struct EditDateField: View {
    let label: String
    @Binding var date: Date?
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).fFont(11.5, .bold).foregroundStyle(FColor.muted)
            Button { picking = true } label: {
                HStack {
                    Text(date.map(TR.dotted) ?? "GG.AA.YYYY").foregroundStyle(date == nil ? FColor.muted : FColor.ink)
                    Spacer()
                    Icon(.calendar, size: 14).foregroundStyle(FColor.muted)
                }
                .fFont(14, .semibold)
                .monospacedDigit()
                .padding(.horizontal, 11)
                .frame(height: 42)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $picking) {
            VStack(spacing: 12) {
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = $0 }), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, TR.locale)
                    .tint(FColor.brand)
                Button("Tamam") { if date == nil { date = Date() }; picking = false }
                    .buttonStyle(.fPrimary)
            }
            .padding(20)
            .fSelfSizingSheet()
        }
    }
}

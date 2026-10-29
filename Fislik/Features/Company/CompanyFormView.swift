import SwiftUI

/// Editable state for `PUT /company`.
struct CompanyDraft: Equatable {
    var fullName = ""
    var tradeName = ""
    var taxOffice = ""
    var taxNumber = ""
    var nationalId = ""
    var businessAddress = ""
    var taxType = "Gelir Vergisi"
    var activityCode = ""
    var activityName = ""
    var startedOn: Date?

    static let taxTypes = ["Gelir Vergisi", "Kurumlar Vergisi", "Basit Usul", "Serbest Meslek"]

    init() {}

    init(_ p: CompanyProfile) {
        fullName = p.fullName
        tradeName = p.tradeName ?? ""
        taxOffice = p.taxOffice
        taxNumber = p.taxNumber
        nationalId = p.nationalId ?? ""
        businessAddress = p.businessAddress
        taxType = p.taxType ?? "Gelir Vergisi"
        activityCode = p.activityCode ?? ""
        activityName = p.activityName ?? ""
        startedOn = p.startedOn.flatMap(DateParsing.parse)
    }

    var profile: CompanyProfile {
        CompanyProfile(
            fullName: fullName.trimmingCharacters(in: .whitespaces),
            tradeName: tradeName.nilIfBlank,
            taxOffice: taxOffice.trimmingCharacters(in: .whitespaces),
            taxNumber: taxNumber,
            nationalId: nationalId.nilIfBlank,
            businessAddress: businessAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            taxType: taxType.nilIfBlank,
            activityCode: activityCode.nilIfBlank,
            activityName: activityName.nilIfBlank,
            startedOn: startedOn.map(DateParsing.dayString)
        )
    }

    var errors: [String: String] {
        var e: [String: String] = [:]
        if fullName.nilIfBlank == nil { e["fullName"] = "Zorunlu alan" }
        if taxOffice.nilIfBlank == nil { e["taxOffice"] = "Zorunlu alan" }
        if taxNumber.count != 10 { e["taxNumber"] = "VKN 10 haneli olmalı" }
        if !nationalId.isEmpty && nationalId.count != 11 { e["nationalId"] = "TCKN 11 haneli olmalı" }
        if businessAddress.nilIfBlank == nil { e["businessAddress"] = "Zorunlu alan" }
        return e
    }
}

/// 2F — company profile; used in onboarding (step 2/2) and from Profile.
struct CompanyFormView: View {
    enum Mode { case onboarding, edit }

    let mode: Mode
    var onFinish: (_ skipped: Bool) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CompanyDraft()
    @State private var original = CompanyDraft()
    @State private var showErrors = false
    @State private var saving = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        let errors = showErrors ? draft.errors : [:]
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    FTextField(label: "Adı Soyadı", text: $draft.fullName, required: true, error: errors["fullName"], contentType: .name, autocapitalization: .words, height: 46)
                    FTextField(label: "Ticaret Ünvanı", text: $draft.tradeName, placeholder: "Örn. Yıldırım Ticaret Ltd. Şti.", contentType: .organizationName, autocapitalization: .words, height: 46)
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            FTextField(label: "Vergi Dairesi", text: $draft.taxOffice, placeholder: "Kadıköy", required: true, error: errors["taxOffice"], autocapitalization: .words, height: 46)
                            DigitsField(label: "VKN (10 hane)", text: $draft.taxNumber, length: 10, required: true, error: errors["taxNumber"])
                        }
                        GridRow {
                            DigitsField(label: "TC Kimlik No", text: $draft.nationalId, length: 11, placeholder: "11 hane", error: errors["nationalId"])
                            DateField(label: "İşe Başlama", date: $draft.startedOn)
                        }
                        GridRow {
                            PickerField(label: "Vergi Türü", selection: $draft.taxType, options: CompanyDraft.taxTypes)
                            FTextField(label: "Faaliyet Kodu", text: $draft.activityCode, placeholder: "47.11.01", keyboard: .numbersAndPunctuation, height: 46)
                        }
                    }
                    FTextField(label: "Faaliyet Adı", text: $draft.activityName, placeholder: "Perakende gıda satışı", height: 46)
                    MultilineField(label: "İş Yeri Adresi", text: $draft.businessAddress, placeholder: "Mahalle, cadde, no, ilçe/il", required: true, error: errors["businessAddress"])
                    AuthErrorText(error: error)
                }
                .padding(16)
                .fCard(radius: 18)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .redacted(reason: loading ? .placeholder : [])
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: save) {
                FButtonLabel(title: mode == .onboarding ? "Kaydet ve başla" : "Kaydet", loading: saving)
            }
            .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
            .disabled(saving || (mode == .edit && draft == original))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(FColor.bg.shadow(color: FColor.ink.opacity(0.08), radius: 10, y: -10).ignoresSafeArea())
        }
        .background(FColor.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(mode == .edit)
        .toolbar(mode == .edit ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if mode == .edit {
                ToolbarItem(placement: .topBarLeading) { FBackButton(title: "Profil") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mode == .onboarding {
                HStack {
                    Text("ADIM 2 / 2").fFont(11, .heavy, tracking: 0.4).foregroundStyle(FColor.brand)
                    Spacer()
                    Button("Şimdilik geç") { onFinish(true) }.fFont(15, .bold).foregroundStyle(FColor.brand)
                }
                .frame(height: 44)
            }
            HStack(spacing: 12) {
                FIconTile(icon: .building, size: 44, iconSize: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Firma Bilgileri").fFont(22, .heavy, tracking: -0.4)
                    Text("Vergi levhandaki bilgiler; muhasebecin görüntüleyebilir.").fFont(12.5, .medium).foregroundStyle(FColor.muted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, mode == .onboarding ? 8 : 0)
    }

    private func load() async {
        defer { loading = false }
        if let profile = try? await API.company() {
            draft = CompanyDraft(profile)
            original = draft
        } else if draft.fullName.isEmpty {
            draft.fullName = app.user?.fullName ?? ""
        }
    }

    private func save() {
        showErrors = true
        guard draft.errors.isEmpty else {
            error = "Yıldızlı alanları doldur."
            return
        }
        error = nil
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try await API.saveCompany(draft.profile)
                original = draft
                if mode == .onboarding { onFinish(false) } else { dismiss() }
            } catch let e as APIError {
                error = e.message
            } catch {}
        }
    }
}

/// Fixed-length numeric field that shows the remaining digits as a ghost (VKN "123456⁷⁸⁹⁰").
struct DigitsField: View {
    let label: String
    @Binding var text: String
    let length: Int
    var placeholder: String?
    var required = false
    var error: String?
    @FocusState private var focused: Bool

    private var ghost: String {
        let sample = String("1234567890123".prefix(length))
        return String(sample.dropFirst(text.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFieldLabel(text: label, required: required)
            ZStack(alignment: .leading) {
                if text.isEmpty && !focused, let placeholder {
                    Text(placeholder).foregroundStyle(FColor.muted.opacity(0.7))
                } else if focused || !text.isEmpty {
                    (Text(text).foregroundColor(.clear) + Text(ghost).foregroundColor(Color(hex: 0xB9C3C1)))
                }
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .onChange(of: text) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(length))
                        if digits != new { text = digits }
                    }
            }
            .fFont(15, .medium)
            .tracking(0.5)
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(focused ? FColor.card : FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(error != nil ? FColor.danger : focused ? FColor.brand : FColor.fieldBorder, lineWidth: focused || error != nil ? 1.5 : 1))
            if let error { Text(error).fFont(11.5, .semibold).foregroundStyle(FColor.danger) }
        }
    }
}

/// "GG.AA.YYYY 📅" date field with a graphical picker sheet.
struct DateField: View {
    let label: String
    @Binding var date: Date?
    var height: CGFloat = 46
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFieldLabel(text: label)
            Button { picking = true } label: {
                HStack {
                    Text(date.map(TR.dotted) ?? "GG.AA.YYYY").foregroundStyle(date == nil ? FColor.muted : FColor.ink)
                    Spacer()
                    Icon(.calendar, size: 15).foregroundStyle(FColor.muted)
                }
                .fFont(15, .medium)
                .padding(.horizontal, 13)
                .frame(height: height)
                .background(FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.fieldBorder))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $picking) {
            VStack {
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = $0 }), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, TR.locale)
                    .tint(FColor.brand)
                HStack {
                    Button("Temizle") { date = nil; picking = false }.buttonStyle(.fSecondary)
                    Button("Tamam") { if date == nil { date = Date() }; picking = false }.buttonStyle(.fPrimary)
                }
            }
            .padding(20)
            .presentationDetents([.medium])
        }
    }
}

/// Dropdown-looking field backed by a Menu.
struct PickerField: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFieldLabel(text: label)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection).foregroundStyle(FColor.ink).lineLimit(1)
                    Spacer()
                    Icon(.chevronDown, size: 15).foregroundStyle(FColor.muted)
                }
                .fFont(15, .medium)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.fieldBorder))
            }
        }
    }
}

struct MultilineField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var required = false
    var error: String?
    var maxLength: Int?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { FFieldLabel(text: label, required: required) }
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...6)
                .focused($focused)
                .fFont(15, .medium)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .frame(minHeight: 74, alignment: .topLeading)
                .background(focused ? FColor.card : FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(error != nil ? FColor.danger : focused ? FColor.brand : FColor.fieldBorder, lineWidth: focused || error != nil ? 1.5 : 1))
                .onChange(of: text) { _, new in
                    if let maxLength, new.count > maxLength { text = String(new.prefix(maxLength)) }
                }
            if let error { Text(error).fFont(11.5, .semibold).foregroundStyle(FColor.danger) }
        }
    }
}

struct CompanySetupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CompanyFormView(mode: .onboarding) { skipped in
            app.companyDone(skipped: skipped)
        }
    }
}

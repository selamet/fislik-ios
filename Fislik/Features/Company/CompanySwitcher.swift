import SwiftUI

/// Home header: active company avatar + "ŞİRKET" eyebrow + name + chevron
/// (design `docs/design/company-tenant/01-company-switcher`). Tapping opens
/// `CompanySwitcherSheet`.
struct CompanyHeaderButton: View {
    let company: CompanyMembership
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Uploaders see their role instead of "ŞİRKET" (design 05-uploader-home).
                let uploader = company.role == .uploader
                FAvatar(
                    initials: company.initials,
                    size: 40,
                    radius: 13,
                    foreground: uploader ? FColor.ink2 : FColor.brand,
                    background: uploader ? FColor.tint : FColor.brand.opacity(0.1)
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(uploader ? "YÜKLEYİCİ" : "ŞİRKET").fFont(11, .bold, tracking: 0.3).foregroundStyle(FColor.muted)
                    HStack(spacing: 4) {
                        Text(company.name).fFont(18, .heavy, tracking: -0.4).lineLimit(1)
                        Icon(.chevronDown, size: 16)
                    }
                    .foregroundStyle(FColor.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Şirket değiştir, aktif şirket \(company.name)")
    }
}

/// Bottom sheet listing the memberships (role, member count, pending uploads
/// per company) plus "Yeni şirket oluştur". With a single membership only the
/// create action is offered — there is nothing to switch to.
struct CompanySwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UploadQueue.self) private var uploads
    @State private var companies = CompanyStore.shared
    @State private var creating = false
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if creating { createForm } else { picker }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(FColor.card.ignoresSafeArea())
        .fSelfSizingSheet()
    }

    // MARK: Picker

    @ViewBuilder
    private var picker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Şirket seç").fFont(21, .heavy, tracking: -0.5).foregroundStyle(FColor.ink)
            Text("Yüklediğin fişler seçtiğin şirkete kaydedilir.").fFont(13, .medium).foregroundStyle(FColor.muted)
        }
        if companies.companies.count > 1 {
            VStack(spacing: 8) {
                ForEach(companies.companies) { company in
                    row(company)
                }
            }
        }
        Button { withAnimation(.snappy) { creating = true } } label: {
            HStack(spacing: 8) {
                Icon(.plus, size: 18)
                Text("Yeni şirket oluştur").fFont(14, .heavy)
            }
            .foregroundStyle(FColor.brand)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private func row(_ company: CompanyMembership) -> some View {
        let selected = company.id == companies.activeId
        let pending = uploads.pendingCount(companyId: company.id)
        return Button {
            companies.select(company.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                FAvatar(
                    initials: company.initials,
                    size: 40,
                    radius: 12,
                    foreground: selected ? FColor.brand : FColor.ink2,
                    background: selected ? FColor.brand.opacity(0.12) : FColor.tint
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name).fFont(15, .heavy).foregroundStyle(FColor.ink).lineLimit(1)
                    Text(company.caption).fFont(12, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer(minLength: 8)
                if pending > 0 && !selected {
                    FTag(text: "\(pending) yükleme bekliyor", color: FColor.warning)
                }
                if selected {
                    Icon(.check, size: 18).foregroundStyle(FColor.brand)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(selected ? FColor.brand.opacity(0.05) : FColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? FColor.brand : FColor.lineStrong, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Create

    @ViewBuilder
    private var createForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Yeni şirket oluştur").fFont(21, .heavy, tracking: -0.5).foregroundStyle(FColor.ink)
            Text("Şirketin sahibi sen olursun. Her şirketin fişleri, kredisi ve ekibi ayrı tutulur.")
                .fFont(13, .medium).foregroundStyle(FColor.muted).fixedSize(horizontal: false, vertical: true)
        }
        FTextField(
            label: "Şirket adı",
            text: $name,
            error: error,
            contentType: .organizationName,
            autocapitalization: .words,
            submitLabel: .done,
            onSubmit: create
        )
        HStack(spacing: 10) {
            Button("Vazgeç") { withAnimation(.snappy) { creating = false; error = nil } }
                .buttonStyle(.fSecondary)
            Button(action: create) { FButtonLabel(title: "Oluştur", loading: saving) }
                .buttonStyle(.fPrimary)
                .disabled(trimmedName.isEmpty || saving)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await companies.create(name: trimmedName)
                dismiss()
            } catch let e as APIError {
                error = e.message
            } catch {}
        }
    }
}

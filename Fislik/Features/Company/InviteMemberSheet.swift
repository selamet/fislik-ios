import SwiftUI

/// Invite sheet (design `03-invite-member`): e-mail + role cards with what
/// each role can do; Yükleyici is preselected and the CTA follows the role.
struct InviteMemberSheet: View {
    var onSent: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var companies = CompanyStore.shared
    @State private var email = ""
    @State private var role: MemberRole = .uploader
    @State private var sending = false
    @State private var error: String?

    private struct Option {
        let role: MemberRole
        let tag: String
        let bullets: [String]
    }

    private let options = [
        Option(role: .uploader, tag: "Önerilen", bullets: [
            "Fiş fotoğrafı çeker ve yükler",
            "Sadece kendi yüklediği fişleri görür",
            "Açık aylarda kendi fişini silebilir",
        ]),
        Option(role: .admin, tag: "Tam erişim", bullets: [
            "Şirketin tüm fişlerini görür ve düzenler",
            "Ayı muhasebeciye gönderir",
            "Üye ve muhasebeci davet eder",
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ekibe üye davet et").fFont(22, .heavy, tracking: -0.5)
                (Text("Davet edilen kişi ")
                    + Text(companies.active?.name ?? "şirketin").foregroundColor(FColor.ink).fontWeight(.bold)
                    + Text(" şirketi için fiş yükleyebilir. Hesabı yoksa e-postadaki bağlantıyla kayıt olur."))
                    .fFont(13, .medium)
                    .foregroundStyle(FColor.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FTextField(
                label: "E-posta",
                text: $email,
                placeholder: "ornek@sirket.com",
                error: error,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                autocapitalization: .never,
                submitLabel: .send,
                height: 50,
                onSubmit: send
            )

            VStack(alignment: .leading, spacing: 10) {
                FFieldLabel(text: "Rol")
                ForEach(options, id: \.role) { option in
                    roleCard(option)
                }
            }

            Button(action: send) {
                FButtonLabel(title: "\(role.label) olarak davet et", loading: sending)
            }
            .buttonStyle(.f(.primary, height: 52))
            .disabled(!email.isValidEmail || sending)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(FColor.card.ignoresSafeArea())
        .fSelfSizingSheet()
        .onChange(of: email) { error = nil }
    }

    private func roleCard(_ option: Option) -> some View {
        let selected = role == option.role
        return Button { role = option.role } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(selected ? FColor.brand : FColor.ink.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .overlay { if selected { Circle().fill(FColor.brand).frame(width: 10, height: 10) } }
                    Text(option.role.label).fFont(15, .heavy)
                    Spacer()
                    Text(option.tag).fFont(11, .bold).foregroundStyle(FColor.muted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(option.bullets, id: \.self) { bullet in
                        HStack(spacing: 7) {
                            Icon(.check, size: 13).foregroundStyle(FColor.success)
                            Text(bullet).fFont(12.5, .semibold).foregroundStyle(FColor.ink2)
                        }
                    }
                }
                .padding(.leading, 30)
            }
            .foregroundStyle(FColor.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func send() {
        guard email.isValidEmail, !sending, let companyId = companies.activeId else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                _ = try await API.inviteMember(companyId, email: email.trimmingCharacters(in: .whitespaces).lowercased(), role: role)
                onSent()
                dismiss()
            } catch let e as APIError {
                switch e.status {
                case 409: error = "Bu kişi zaten ekipte ya da davet edilmiş"
                case 422: error = "Bu e-posta bir muhasebeci hesabına ait"
                case 403: error = "Üye davet etme yetkin yok"
                default: error = e.message
                }
            } catch {}
        }
    }
}

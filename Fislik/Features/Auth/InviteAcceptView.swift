import SwiftUI

/// 2E — opened from `fislik.selamet.dev/davet/{token}` while signed out.
struct InviteAcceptView: View {
    let token: String
    @Environment(AppModel.self) private var app
    @Environment(AuthModel.self) private var auth
    @State private var preview: InvitePreview?
    @State private var loadError: String?
    @State private var name = ""
    @State private var password = ""

    private var inviterIsAccountant: Bool { preview?.inviterRole == .accountant }

    var body: some View {
        AuthPage(back: "Geri") {
            Group {
                if let preview {
                    content(preview)
                } else if let loadError {
                    AuthCard { AuthErrorText(error: loadError) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.top, 20)
        }
        .task { await load() }
    }

    private func content(_ preview: InvitePreview) -> some View {
        let inviter = preview.inviterName ?? "Muhasebecin"
        return VStack(spacing: 14) {
            HStack(spacing: -14) {
                FAvatar(initials: inviter.initials, size: 62, radius: 20)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(FColor.card, lineWidth: 3))
                Icon(.users, size: 24)
                    .foregroundStyle(FColor.brand)
                    .frame(width: 62, height: 62)
                    .background(FColor.bg, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(FColor.card, lineWidth: 3))
            }
            VStack(spacing: 6) {
                Text("\(inviter) seni Fişlik'e davet etti").fFont(19, .heavy, tracking: -0.3).multilineTextAlignment(.center)
                Text(inviterIsAccountant
                     ? "Muhasebecin olarak fiş ve faturalarını Fişlik üzerinden toplamak istiyor."
                     : "Seni muhasebecisi olarak eklemek istiyor; fişlerini Fişlik üzerinden görebileceksin.")
                    .fFont(13, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.center).lineSpacing(3)
            }
            HStack(alignment: .top, spacing: 10) {
                Icon(.shieldCheck, size: 16).foregroundStyle(FColor.brand).padding(.top, 1)
                (Text("Yalnızca ") + Text("görüntüleme ve indirme").bold().foregroundColor(FColor.ink) + Text(" yetkisi alır. Erişimi istediğin an kaldırabilirsin."))
                    .fFont(12, .medium).foregroundStyle(FColor.muted)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(FColor.bg, in: RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 12) {
                FTextField(label: "Ad Soyad", text: $name, placeholder: "Adın ve soyadın", contentType: .name, autocapitalization: .words)
                FTextField(label: "E-posta", text: .constant(preview.invitedEmail), disabled: true, trailingIcon: .lock)
                FTextField(label: "Şifre", text: $password, placeholder: "En az 8 karakter", secure: true, contentType: .newPassword, autocapitalization: .never)
            }

            AuthErrorText(error: auth.error)

            Button {
                auth.inviteToken = token
                Task { await auth.register(app: app, name: name, email: preview.invitedEmail, password: password, role: preview.invitedRole ?? .client) }
            } label: {
                FButtonLabel(title: "Daveti kabul et ve hesap oluştur", loading: auth.busy)
            }
            .buttonStyle(.fPrimary)
            .disabled(name.nilIfBlank == nil || password.count < 8 || auth.busy)

            HStack(spacing: 4) {
                Text("Zaten hesabın var mı?").foregroundStyle(FColor.muted)
                Button("Giriş yapıp kabul et") {
                    auth.inviteToken = token
                    auth.path.removeAll()
                }
                .fontWeight(.bold)
                .foregroundStyle(FColor.brand)
            }
            .fFont(12.5, .semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(FColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(FColor.line))
        .shadow(color: Color(hex: 0x0C1A18).opacity(0.12), radius: 20, y: 18)
    }

    private func load() async {
        do {
            preview = try await API.invitePreview(token: token)
        } catch let e as APIError {
            loadError = e.status == 404 ? "Bu davet bulunamadı ya da süresi dolmuş." : e.message
        } catch {
            loadError = APIError.transport(code: 0).message
        }
    }
}

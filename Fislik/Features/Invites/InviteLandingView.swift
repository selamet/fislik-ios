import SwiftUI

/// Header + benefits card shared by the invite landing and the signed-in invite sheet.
struct InviteSummary: View {
    let info: InviteLookup

    var body: some View {
        VStack(spacing: 14) {
            FAvatar(initials: (info.companyName ?? info.inviterName ?? "F").initials, size: 62, radius: 20)
            VStack(spacing: 6) {
                Text(InviteCopy.badge(info)).fFont(11, .heavy, tracking: 0.6).foregroundStyle(FColor.brand)
                Text(InviteCopy.headline(info))
                    .fFont(19, .heavy, tracking: -0.3)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(InviteCopy.benefits(kind: info.kind, role: info.role), id: \.self) { text in
                    HStack(spacing: 10) {
                        Icon(.check, size: 15).foregroundStyle(FColor.brand)
                        Text(text).fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .background(FColor.bg, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Card chrome used by the invite screens.
struct InviteCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 14, content: content)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(FColor.line))
            .shadow(color: Color(hex: 0x0C1A18).opacity(0.12), radius: 20, y: 18)
    }
}

/// Opened from `/uye-davet/{token}` or `/davet/{token}` while signed out, in
/// place of the intro pager: explains the invite and takes the visitor to
/// "joined" — create an account (e-mail locked to the invite), log in, or
/// continue with Apple/Google — or lets them decline without an account.
struct InviteLandingView: View {
    let token: String
    @Environment(AppModel.self) private var app
    @Environment(AuthModel.self) private var auth
    @State private var info: InviteLookup?
    @State private var loadError: String?
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var declined = false
    @State private var declining = false

    var body: some View {
        AuthPage(back: "Geri") {
            Group {
                if declined {
                    InviteCard {
                        Text("Daveti reddettin").fFont(19, .heavy)
                        Text("Davet eden tarafa haber verdik.").fFont(13, .medium).foregroundStyle(FColor.muted)
                    }
                } else if let info {
                    content(info)
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

    private func content(_ info: InviteLookup) -> some View {
        let verb = info.kind == .member ? "katıl" : "bağlan"
        return InviteCard {
            InviteSummary(info: info)
            VStack(spacing: 12) {
                if info.accountExists {
                    FTextField(label: "E-posta", text: $email, keyboard: .emailAddress, contentType: .emailAddress, autocapitalization: .never)
                    FTextField(label: "Şifre", text: $password, placeholder: "Şifren", secure: true, contentType: .password, autocapitalization: .never)
                } else {
                    FTextField(label: "Ad Soyad", text: $name, placeholder: "Adın ve soyadın", contentType: .name, autocapitalization: .words)
                    FTextField(label: "E-posta", text: .constant(info.email), disabled: true, trailingIcon: .lock)
                    FTextField(label: "Şifre", text: $password, placeholder: "En az 8 karakter", secure: true, contentType: .newPassword, autocapitalization: .never)
                }
            }

            AuthErrorText(error: auth.error)

            Button {
                Task {
                    if info.accountExists {
                        await auth.login(app: app, email: email, password: password)
                    } else {
                        await auth.register(app: app, name: name, email: info.email, password: password, role: info.invitedAccountRole)
                    }
                }
            } label: {
                FButtonLabel(title: info.accountExists ? "Giriş yap ve \(verb)" : "Hesap aç ve \(verb)", loading: auth.busy)
            }
            .buttonStyle(.fPrimary)
            .disabled(auth.busy || password.isEmpty || (!info.accountExists && (name.nilIfBlank == nil || password.count < 8)))

            if info.accountExists {
                Button("Şifremi unuttum") { auth.path.append(.forgot) }
                    .fFont(12.5, .bold)
                    .foregroundStyle(FColor.brand)
            }

            SocialButtons(busy: auth.busy) {
                Task { await auth.appleSignIn(app: app) }
            } onGoogle: {
                Task { await auth.googleSignIn(app: app) }
            }

            Button("Bu daveti istemiyorum") { Task { await decline() } }
                .fFont(12, .semibold)
                .foregroundStyle(FColor.muted)
                .disabled(declining)
        }
    }

    private func load() async {
        do {
            let lookup = try await API.invite(token: token)
            info = lookup
            email = lookup.email
            auth.pendingInvite = PendingInvite(kind: lookup.kind, token: token, role: lookup.invitedAccountRole)
        } catch let e as APIError {
            auth.pendingInvite = nil
            loadError = e.status == 404 ? "Bu davet bulunamadı ya da daha önce kullanılmış." : e.message
        } catch {
            auth.pendingInvite = nil
            loadError = APIError.transport(code: 0).message
        }
    }

    private func decline() async {
        declining = true
        defer { declining = false }
        do {
            try await API.declineInvite(token: token)
            auth.pendingInvite = nil
            declined = true
        } catch let e as APIError {
            auth.error = e.status == 404 ? InviteCopy.gone : e.message
        } catch {
            auth.error = APIError.transport(code: 0).message
        }
    }
}

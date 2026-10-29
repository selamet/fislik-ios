import SafariServices
import SwiftUI

/// 2D (top) — request a reset link.
struct ForgotPasswordView: View {
    @Environment(AuthModel.self) private var auth
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        AuthPage(back: "Giriş") {
            AuthCard(padding: 20) {
                FIconTile(icon: .keyRound, size: 52, iconSize: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Şifreni sıfırla").fFont(20, .heavy, tracking: -0.4)
                    Text("Hesabının e-postasını gir; sıfırlama bağlantısı gönderelim. Bağlantı 30 dakika geçerlidir.")
                        .fFont(13, .medium).foregroundStyle(FColor.muted).lineSpacing(3)
                }
                FTextField(label: "E-posta", text: $email, placeholder: "ornek@firma.com", keyboard: .emailAddress, contentType: .emailAddress, autocapitalization: .never, submitLabel: .send) { submit() }

                if sent {
                    FBanner(icon: .circleCheck, tone: .success, text: Text("Bağlantı gönderildi. E-postanı kontrol et; bağlantıya tıkladığında uygulama açılır."))
                }
                AuthErrorText(error: auth.error)

                Button(action: submit) {
                    FButtonLabel(title: sent ? "Tekrar gönder" : "Bağlantı gönder", icon: .mail, loading: auth.busy)
                }
                .buttonStyle(.fPrimary)
                .disabled(!email.isValidEmail || auth.busy)
            }
            .padding(.top, 20)
        }
        .onAppear { auth.error = nil }
    }

    private func submit() {
        guard email.isValidEmail else { return }
        Task {
            await auth.run({
                try await API.requestPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                sent = true
            })
        }
    }
}

/// 2D (bottom) — opened from the e-mail link.
struct NewPasswordView: View {
    let token: String
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var done = false

    private var mismatch: Bool { !repeatPassword.isEmpty && password != repeatPassword }
    private var valid: Bool { password.count >= 8 && password == repeatPassword }

    var body: some View {
        AuthPage(back: "Giriş") {
            Text("BAĞLANTIDAN GELİNCE")
                .fFont(11, .heavy, tracking: 0.4)
                .foregroundStyle(FColor.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 14)
            AuthCard(padding: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Yeni şifre belirle").fFont(18, .heavy, tracking: -0.3)
                    Text("En az 8 karakter kullan.").fFont(12.5, .medium).foregroundStyle(FColor.muted)
                }
                FTextField(label: "Yeni şifre", text: $password, placeholder: "En az 8 karakter", secure: true, contentType: .newPassword, autocapitalization: .never)
                FTextField(label: "Yeni şifre (tekrar)", text: $repeatPassword, secure: true, error: mismatch ? "Yeni şifreler birbiriyle eşleşmiyor" : nil, contentType: .newPassword, autocapitalization: .never, submitLabel: .done) { submit() }

                if done {
                    FBanner(icon: .circleCheck, tone: .success, text: Text("Şifren güncellendi. Yeni şifrenle giriş yapabilirsin."))
                }
                AuthErrorText(error: auth.error)

                Button(done ? "Giriş yap" : "Şifreyi güncelle") {
                    if done { dismiss() } else { submit() }
                }
                .buttonStyle(.fPrimary)
                .disabled(!done && (!valid || auth.busy))
            }
        }
        .onAppear { auth.error = nil }
    }

    private func submit() {
        guard valid else { return }
        Task {
            await auth.run({
                try await API.confirmPasswordReset(token: token, newPassword: password)
                done = true
            }, map: { e in e.status == 400 ? "Bağlantının süresi dolmuş. Yeni bir bağlantı iste." : nil })
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(FColor.brand)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

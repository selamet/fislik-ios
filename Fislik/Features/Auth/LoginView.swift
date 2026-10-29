import LocalAuthentication
import SwiftUI

/// 2B — "Tekrar hoş geldin".
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @Environment(AuthModel.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    enum Field { case email, password }

    private var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var body: some View {
        @Bindable var app = app
        AuthPage(back: nil) {
            VStack(spacing: 10) {
                FislikMark(height: 56)
                Text("Tekrar hoş geldin").fFont(24, .heavy, tracking: -0.5)
                Text("Fişlerin ve muhasebecin seni bekliyor.").fFont(13.5, .medium).foregroundStyle(FColor.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)

            SocialButtons(busy: auth.busy) {
                Task { await auth.appleSignIn(app: app) }
            } onGoogle: {
                Task { await auth.googleSignIn(app: app) }
            }

            FOrDivider(text: "veya e-posta ile").padding(.vertical, 18)

            AuthCard {
                FTextField(label: "E-posta", text: $email, placeholder: "ornek@firma.com", keyboard: .emailAddress, contentType: .username, autocapitalization: .never) {
                    focus = .password
                }
                .focused($focus, equals: .email)
                FTextField(label: "Şifre", text: $password, placeholder: "Şifren", secure: true, contentType: .password, autocapitalization: .never, submitLabel: .go) {
                    submit()
                }
                .focused($focus, equals: .password)

                HStack {
                    if biometryAvailable {
                        Button {
                            app.faceIDEnabled.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Icon(.scanFace, size: 16)
                                Text(app.faceIDEnabled ? "Face ID açık" : "Face ID kapalı")
                            }
                            .fFont(12.5, .semibold)
                            .foregroundStyle(app.faceIDEnabled ? FColor.muted : FColor.faint)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    NavigationLink(value: AuthRoute.forgot) {
                        Text("Şifremi unuttum").fFont(12.5, .bold).foregroundStyle(FColor.brand)
                    }
                }

                AuthErrorText(error: auth.error)

                Button(action: submit) {
                    FButtonLabel(title: "Giriş yap", loading: auth.busy)
                }
                .buttonStyle(.fPrimary)
                .disabled(auth.busy || !email.isValidEmail || password.isEmpty)
            }

            HStack(spacing: 4) {
                Text("Hesabın yok mu?").foregroundStyle(FColor.muted)
                NavigationLink(value: AuthRoute.register) {
                    Text("Kayıt ol").fontWeight(.bold).foregroundStyle(FColor.brand)
                }
            }
            .fFont(13, .semibold)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
        .onAppear { auth.error = nil }
    }

    private func submit() {
        guard email.isValidEmail, !password.isEmpty else { return }
        focus = nil
        Task { await auth.login(app: app, email: email, password: password) }
    }
}

/// Cold start with Face ID enabled.
struct FaceIDLockView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            FislikMark(height: 64)
            Text("Fişlik kilitli").fFont(22, .heavy, tracking: -0.4)
            Text("Devam etmek için Face ID ile doğrula.").fFont(13.5, .medium).foregroundStyle(FColor.muted)
            Spacer()
            Button {
                Task { await app.unlockWithFaceID() }
            } label: {
                FButtonLabel(title: "Face ID ile aç", icon: .scanFace)
            }
            .buttonStyle(.fPrimary)
            Button("Şifre ile giriş yap") { app.signOutLocally() }
                .fFont(13.5, .bold)
                .foregroundStyle(FColor.brand)
        }
        .padding(24)
        .background(FAuthBackground())
        .task { await app.unlockWithFaceID() }
    }
}

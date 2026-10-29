import SwiftUI

/// 2C — role selection + account details.
struct RegisterView: View {
    @Environment(AppModel.self) private var app
    @Environment(AuthModel.self) private var auth
    @State private var role: UserRole = .client
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showTerms: URL?

    private var valid: Bool {
        name.nilIfBlank != nil && email.isValidEmail && password.count >= 8
    }

    var body: some View {
        AuthPage(title: "Kayıt ol") {
            VStack(alignment: .leading, spacing: 14) {
                Text("FİŞLİK'İ NASIL KULLANACAKSIN?").fFont(12.5, .bold, tracking: 0.2).foregroundStyle(FColor.muted)
                    .padding(.top, 12)
                RoleCards(role: $role)

                VStack(alignment: .leading, spacing: 12) {
                    FTextField(label: "Ad Soyad", text: $name, placeholder: "Adın ve soyadın", contentType: .name, autocapitalization: .words)
                    FTextField(label: "E-posta", text: $email, placeholder: "ornek@firma.com", keyboard: .emailAddress, contentType: .emailAddress, autocapitalization: .never)
                    VStack(alignment: .leading, spacing: 6) {
                        FTextField(label: "Şifre", text: $password, placeholder: "En az 8 karakter", secure: true, contentType: .newPassword, autocapitalization: .never, submitLabel: .go) { submit() }
                        PasswordStrengthBar(password: password).padding(.top, 2)
                    }
                }
                .padding(16)
                .fCard(radius: 20)
                .padding(.top, 4)

                FOrDivider(text: "veya")

                SocialButtons(compact: true, busy: auth.busy) {
                    Task { await auth.appleSignIn(app: app) }
                } onGoogle: {
                    Task { await auth.googleSignIn(app: app) }
                }

                AuthErrorText(error: auth.error)

                TermsText(onOpen: { showTerms = $0 })
                    .padding(.top, 10)

                Button(action: submit) {
                    FButtonLabel(title: "Hesap oluştur", loading: auth.busy)
                }
                .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
                .disabled(!valid || auth.busy)
            }
        }
        .onAppear { auth.error = nil }
        .sheet(item: $showTerms) { SafariView(url: $0).ignoresSafeArea() }
    }

    private func submit() {
        guard valid else { return }
        Task { await auth.register(app: app, name: name, email: email, password: password, role: role) }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct RoleCards: View {
    @Binding var role: UserRole

    var body: some View {
        VStack(spacing: 14) {
            card(.client, icon: .store, title: "Fiş yüklüyorum", subtitle: "İşletme sahibiyim, fişlerimi fotoğraflayacağım")
            card(.accountant, icon: .users, title: "Muhasebeciyim", subtitle: "Mükelleflerimin fişlerini görüntüleyeceğim")
        }
    }

    private func card(_ value: UserRole, icon: FIcon, title: String, subtitle: String) -> some View {
        let selected = role == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { role = value }
        } label: {
            HStack(spacing: 12) {
                Icon(icon, size: 22)
                    .foregroundStyle(selected ? .white : FColor.muted)
                    .frame(width: 44, height: 44)
                    .background(selected ? FColor.brand : Color(light: 0xF3F4F6, dark: 0x22302E), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fFont(15.5, .heavy).foregroundStyle(FColor.ink)
                    Text(subtitle).fFont(12.5, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                ZStack {
                    if selected {
                        Circle().fill(FColor.brand)
                        Icon(.check, size: 13).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(FColor.fieldBorder, lineWidth: 2)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(14)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(selected ? FColor.brand : FColor.fieldBorder, lineWidth: 2))
            .shadow(color: selected ? FColor.brand.opacity(0.35) : .clear, radius: 14, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Four-segment strength meter under the password field.
struct PasswordStrengthBar: View {
    let password: String

    static func score(_ p: String) -> Int {
        guard !p.isEmpty else { return 0 }
        var s = 0
        if p.count >= 8 { s += 1 }
        if p.count >= 12 { s += 1 }
        if p.rangeOfCharacter(from: .decimalDigits) != nil && p.rangeOfCharacter(from: .letters) != nil { s += 1 }
        if p.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil || (p.lowercased() != p && p.uppercased() != p) { s += 1 }
        return max(1, s)
    }

    var body: some View {
        let score = Self.score(password)
        let color = score <= 1 ? FColor.danger : score == 2 ? FColor.warning : FColor.success
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i < score ? color : FColor.ink.opacity(0.1)).frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.2), value: score)
        .accessibilityLabel("Şifre gücü \(score)/4")
    }
}

struct TermsText: View {
    let onOpen: (URL) -> Void

    var body: some View {
        Text("Devam ederek [Kullanım Koşulları](\(APIConfig.webURL.appendingPathComponent("kosullar").absoluteString)) ve [Gizlilik Politikası](\(APIConfig.webURL.appendingPathComponent("gizlilik").absoluteString))'nı kabul edersin.")
            .fFont(11.5, .medium)
            .foregroundStyle(FColor.muted)
            .tint(FColor.brand)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.openURL, OpenURLAction { url in
                onOpen(url)
                return .handled
            })
    }
}

/// 2C social follow-up: Google/Apple account without a Fişlik role yet.
struct RolePickerView: View {
    let registrationToken: String
    @Environment(AppModel.self) private var app
    @Environment(AuthModel.self) private var auth
    @State private var role: UserRole = .client

    var body: some View {
        AuthPage(title: "Kayıt ol") {
            VStack(alignment: .leading, spacing: 14) {
                Text("FİŞLİK'İ NASIL KULLANACAKSIN?").fFont(12.5, .bold, tracking: 0.2).foregroundStyle(FColor.muted)
                    .padding(.top, 12)
                RoleCards(role: $role)
                AuthErrorText(error: auth.error)
                Button {
                    Task { await auth.completeOAuth(app: app, token: registrationToken, role: role) }
                } label: {
                    FButtonLabel(title: "Hesap oluştur", loading: auth.busy)
                }
                .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
                .padding(.top, 10)
            }
        }
    }
}

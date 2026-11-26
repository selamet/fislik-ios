import SwiftUI

/// Copy for the API's 400 details on POST /auth/email/verify.
enum EmailCodeCopy {
    static func message(for error: APIError) -> String {
        switch (error.status, error.detail) {
        case (400, "Invalid code"?): "Kod hatalı. Tekrar dene."
        case (400, "Code expired"?): "Kodun süresi doldu. Yeni kod iste."
        case (400, "Too many attempts"?): "Çok fazla hatalı deneme. Yeni kod iste."
        case (400, "No active code"?): "Geçerli bir kod yok. Yeni kod iste."
        case (429, _): "Çok sık denedin. Biraz bekleyip tekrar dene."
        default: error.message
        }
    }

    /// Digits only, at most six — what the code field accepts.
    static func sanitize(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(6))
    }
}

/// Strip over the main tabs while a classic account hasn't proven its
/// address (`user.emailVerified == false`). Not blocking: it only opens the
/// code sheet. Invites sent to the address reach the account once verified.
struct EmailVerifyBanner: View {
    @Environment(AppModel.self) private var app
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 10) {
                Icon(.mail, size: 16).foregroundStyle(FColor.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("E-posta adresini doğrula").fFont(13, .heavy).foregroundStyle(FColor.ink)
                    Text("Gönderdiğimiz 6 haneli kodu gir").fFont(11.5, .medium).foregroundStyle(FColor.muted)
                }
                Spacer(minLength: 0)
                Text("Kodu gir").fFont(12.5, .bold).foregroundStyle(FColor.brand)
                Icon(.chevronRight, size: 14).foregroundStyle(FColor.brand)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FColor.brand.opacity(0.08).ignoresSafeArea(edges: .top))
            .background(FColor.bg.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) { Rectangle().fill(FColor.brand.opacity(0.2)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Doğrulama kodunu girme ekranını açar")
        .sheet(isPresented: $showSheet) {
            EmailVerifySheet(email: app.user?.email ?? "") { user in
                app.emailVerified(user)
            }
        }
    }
}

/// Code entry: one numeric field (SMS/mail one-time-code autofill), verify
/// and resend.
struct EmailVerifySheet: View {
    let email: String
    var onVerified: (User) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var verifying = false
    @State private var resending = false
    @State private var error: String?
    @State private var info: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("E-postanı doğrula").fFont(22, .heavy, tracking: -0.4)
                Text("\(Text(email).bold()) adresine 6 haneli bir kod gönderdik. Bu adrese gelen davetleri doğruladıktan sonra görebilirsin.")
                    .fFont(12.5, .medium).foregroundStyle(FColor.muted).lineSpacing(3)
            }
            TextField("", text: $code, prompt: Text(verbatim: "000000").foregroundColor(FColor.muted.opacity(0.6)))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .tracking(8)
                .frame(height: 58)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(error != nil ? FColor.danger.opacity(0.6) : focused ? FColor.brand : FColor.fieldBorder, lineWidth: 1.5))
                .accessibilityLabel("Doğrulama kodu")
                .onChange(of: code) { _, new in
                    let clean = EmailCodeCopy.sanitize(new)
                    if clean != new { code = clean }
                    error = nil
                    if clean.count == 6 && !verifying { verify() }
                }
            if let error {
                HStack(spacing: 8) {
                    Icon(.circleAlert, size: 15)
                    Text(error)
                }
                .fFont(12, .semibold)
                .foregroundStyle(FColor.danger)
            } else if let info {
                Text(info).fFont(12, .semibold).foregroundStyle(FColor.muted)
            }
            Button(action: verify) { FButtonLabel(title: "Doğrula", icon: .check, loading: verifying) }
                .buttonStyle(.fPrimary)
                .disabled(code.count != 6 || verifying)
            Button(action: resend) {
                Text(resending ? "Gönderiliyor…" : "Kodu tekrar gönder")
                    .fFont(13.5, .bold)
                    .foregroundStyle(FColor.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(resending)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(FColor.bg.ignoresSafeArea())
        .fSelfSizingSheet()
        .onAppear { focused = true }
    }

    private func verify() {
        guard code.count == 6, !verifying else { return }
        verifying = true
        Task {
            defer { verifying = false }
            do {
                let user = try await API.verifyEmail(code: code)
                onVerified(user)
                dismiss()
            } catch let e as APIError where !e.isCancellation {
                error = EmailCodeCopy.message(for: e)
            } catch {}
        }
    }

    private func resend() {
        resending = true
        Task {
            defer { resending = false }
            do {
                try await API.resendEmailCode()
                code = ""
                error = nil
                info = "Yeni kod e-posta adresine gönderildi."
            } catch let e as APIError where !e.isCancellation {
                error = EmailCodeCopy.message(for: e)
            } catch {}
        }
    }
}

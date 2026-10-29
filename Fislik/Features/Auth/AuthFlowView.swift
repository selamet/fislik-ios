import SwiftUI

enum AuthRoute: Hashable {
    case register
    case forgot
    case newPassword(token: String)
    case invite(token: String)
    case rolePicker(registrationToken: String)
}

/// Shared auth actions (email, Apple, Google) for login/register/invite screens.
@MainActor
@Observable
final class AuthModel {
    var busy = false
    var error: String?
    var path: [AuthRoute] = []
    var inviteToken: String?

    private let apple = AppleSignIn()
    private let google = GoogleSignIn()

    func run(_ work: () async throws -> Void, map: (APIError) -> String? = { _ in nil }) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch let e as APIError {
            error = map(e) ?? e.message
        } catch let e as SocialAuthError {
            error = e.errorDescription
        } catch {
            self.error = APIError.transport(code: 0).message
        }
    }

    func login(app: AppModel, email: String, password: String) async {
        await run({
            let auth = try await API.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            await app.signedIn(auth)
            await acceptPendingInvite()
        }, map: { e in
            switch e.status {
            case 401: "E-posta veya şifre hatalı."
            case 403: "Bu hesap Google ile açılmış. Google ile devam et."
            default: nil
            }
        })
    }

    func register(app: AppModel, name: String, email: String, password: String, role: UserRole) async {
        await run({
            let auth = try await API.register(email: email.trimmingCharacters(in: .whitespaces), password: password, fullName: name.trimmingCharacters(in: .whitespaces), role: role, inviteToken: inviteToken)
            await app.signedIn(auth)
        }, map: { e in e.status == 409 ? "Bu e-posta ile zaten bir hesap var." : nil })
    }

    func appleSignIn(app: AppModel) async {
        await run({
            let result = try await apple.signIn()
            try await handle(try await API.apple(identityToken: result.token, fullName: result.name), app: app)
        }, map: { e in e.status == 404 || e.status == 405 ? "Apple ile giriş çok yakında. Şimdilik e-posta ile devam et." : nil })
    }

    func googleSignIn(app: AppModel) async {
        await run({
            let idToken = try await google.signIn()
            try await handle(try await API.google(idToken: idToken), app: app)
        }, map: { e in
            switch e.status {
            case 401: "Google hesabı doğrulanamadı."
            case 400: "Google hesabının e-postası doğrulanmamış."
            default: nil
            }
        })
    }

    private func handle(_ result: OAuthResult, app: AppModel) async throws {
        switch result.status {
        case .loggedIn:
            guard let user = result.user else { throw SocialAuthError.failed }
            await app.signedIn(user)
            await acceptPendingInvite()
        case .needsRole:
            guard let token = result.registrationToken else { throw SocialAuthError.failed }
            path.append(.rolePicker(registrationToken: token))
        }
    }

    func completeOAuth(app: AppModel, token: String, role: UserRole) async {
        await run({
            let auth = try await API.oauthRegister(token: token, role: role)
            await app.signedIn(auth)
            await acceptPendingInvite()
        }, map: { e in e.status == 401 ? "Süre doldu, tekrar giriş yap." : nil })
    }

    /// After logging in from the invite screen, accept the invite with the new session.
    private func acceptPendingInvite() async {
        guard let token = inviteToken else { return }
        _ = try? await API.acceptInvite(token: token)
        inviteToken = nil
    }
}

struct AuthFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model = AuthModel()

    var body: some View {
        NavigationStack(path: $model.path) {
            LoginView()
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .register: RegisterView()
                    case .forgot: ForgotPasswordView()
                    case .newPassword(let token): NewPasswordView(token: token)
                    case .invite(let token): InviteAcceptView(token: token)
                    case .rolePicker(let token): RolePickerView(registrationToken: token)
                    }
                }
        }
        .environment(model)
        .onAppear(perform: consumeLink)
        .onChange(of: app.pendingLink) { consumeLink() }
    }

    private func consumeLink() {
        switch app.pendingLink {
        case .invite(let token):
            model.path = [.invite(token: token)]
            app.pendingLink = nil
        case .passwordReset(let token):
            model.path = [.newPassword(token: token)]
            app.pendingLink = nil
        default:
            break
        }
    }
}

/// Common page chrome for auth screens: gradient background, custom back button, scrolling content.
struct AuthPage<Content: View>: View {
    var back: String? = "Geri"
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if back != nil || title != nil {
                FNavHeader(back: back, title: title)
                    .padding(.leading, 12)
                    .padding(.trailing, 20)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(FAuthBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// White elevated form card (radius 20, soft shadow).
struct AuthCard<Content: View>: View {
    var spacing: CGFloat = 14
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(FColor.line))
            .shadow(color: Color(hex: 0x0C1A18).opacity(0.12), radius: 20, y: 18)
    }
}

struct AuthErrorText: View {
    let error: String?

    var body: some View {
        if let error {
            HStack(alignment: .top, spacing: 8) {
                Icon(.circleAlert, size: 15).padding(.top, 1)
                Text(error).fFont(12.5, .semibold)
            }
            .foregroundStyle(FColor.danger)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FColor.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(FColor.danger.opacity(0.25)))
        }
    }
}

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
    /// The invite (either kind) the visitor came through, kept while they
    /// register, log in or detour through Apple/Google.
    var pendingInvite: PendingInvite?
    /// Apple's single-use authorization code, held until the role picker creates the account.
    private var pendingAppleCode: String?

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
            await app.signedIn(auth, inviteInProgress: pendingInvite != nil)
            await acceptPendingInvite(app: app)
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
            let tokens = inviteTokens(for: role)
            let auth = try await API.register(email: email.trimmingCharacters(in: .whitespaces), password: password, fullName: name.trimmingCharacters(in: .whitespaces), role: role, inviteToken: tokens.grant, memberInviteToken: tokens.member)
            pendingInvite = nil
            await app.signedIn(auth)
        }, map: { e in e.status == 409 ? "Bu e-posta ile zaten bir hesap var." : nil })
    }

    func appleSignIn(app: AppModel) async {
        await run({
            let result = try await apple.signIn()
            pendingAppleCode = result.code
            try await handle(try await API.apple(identityToken: result.token, authorizationCode: result.code, fullName: result.name), app: app)
        }, map: { e in
            switch e.status {
            case 401: "Apple hesabı doğrulanamadı."
            case 400: "Apple hesabının e-postası doğrulanmamış."
            default: nil
            }
        })
    }

    func googleSignIn(app: AppModel) async {
        await run({
            let idToken = try await google.signIn()
            pendingAppleCode = nil
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
            await app.signedIn(user, inviteInProgress: pendingInvite != nil)
            await acceptPendingInvite(app: app)
        case .needsRole:
            guard let token = result.registrationToken else { throw SocialAuthError.failed }
            path.append(.rolePicker(registrationToken: token))
        }
    }

    func completeOAuth(app: AppModel, token: String, role: UserRole) async {
        await run({
            let tokens = inviteTokens(for: role)
            let auth = try await API.oauthRegister(token: token, role: role, authorizationCode: pendingAppleCode, inviteToken: tokens.grant, memberInviteToken: tokens.member)
            pendingAppleCode = nil
            pendingInvite = nil
            await app.signedIn(auth)
        }, map: { e in e.status == 401 ? "Süre doldu, tekrar giriş yap." : nil })
    }

    /// Forgets the invite once its landing is no longer on the stack (the
    /// visitor went back), so a later plain login doesn't accept it silently.
    func syncInviteWithPath() {
        let onInvite = path.contains { if case .invite = $0 { true } else { false } }
        if !onInvite { pendingInvite = nil }
    }

    /// The registration field carrying the pending invite, when it is for this role.
    private func inviteTokens(for role: UserRole) -> (grant: String?, member: String?) {
        guard let invite = pendingInvite, invite.role == role else { return (nil, nil) }
        return invite.kind == .member ? (nil, invite.token) : (invite.token, nil)
    }

    /// After logging in through an invite, accept it with the new session.
    /// Anything that needs a choice or an explanation (several companies,
    /// wrong account, invite gone) opens the signed-in invite sheet instead.
    private func acceptPendingInvite(app: AppModel) async {
        guard let invite = pendingInvite else { return }
        pendingInvite = nil
        let link: AppModel.DeepLink = invite.kind == .member ? .memberInvite(token: invite.token) : .invite(token: invite.token)
        var companyId: String?
        if invite.kind == .grant, app.user?.role == .client {
            let managed = CompanyStore.shared.companies.filter { $0.role != .uploader }
            guard managed.count == 1 else { app.pendingLink = link; return }
            companyId = managed[0].id
        }
        do {
            await app.didJoin(try await API.acceptInvite(token: invite.token, companyId: companyId))
        } catch {
            app.pendingLink = link
        }
    }
}

/// An invite link the visitor is in the middle of accepting.
struct PendingInvite: Equatable {
    let kind: InviteKind
    let token: String
    /// The account role the invite is for.
    let role: UserRole
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
                    case .invite(let token): InviteLandingView(token: token)
                    case .rolePicker(let token): RolePickerView(registrationToken: token)
                    }
                }
        }
        .environment(model)
        .onAppear(perform: consumeLink)
        .onChange(of: app.pendingLink) { consumeLink() }
        .onChange(of: model.path) { model.syncInviteWithPath() }
    }

    private func consumeLink() {
        switch app.pendingLink {
        case .invite(let token), .memberInvite(let token):
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

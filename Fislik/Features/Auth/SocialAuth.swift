import AuthenticationServices
import CryptoKit
import SwiftUI

enum SocialAuthError: LocalizedError {
    case cancelled
    case notConfigured
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case .notConfigured: "Bu giriş yöntemi henüz etkin değil."
        case .failed: "Giriş tamamlanamadı, tekrar dene."
        }
    }
}

/// Sign in with Apple → identity token (JWT) + optional full name.
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<(token: String, name: String?), Error>?

    func signIn() async throws -> (token: String, name: String?) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let name = credential?.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0).nilIfBlank }
        Task { @MainActor in
            if let token {
                continuation?.resume(returning: (token, name))
            } else {
                continuation?.resume(throwing: SocialAuthError.failed)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            continuation?.resume(throwing: cancelled ? SocialAuthError.cancelled : SocialAuthError.failed)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.keyWindow ?? ASPresentationAnchor() }
    }
}

/// Google OAuth (authorization code + PKCE) through ASWebAuthenticationSession; returns the ID token.
/// Requires an iOS OAuth client id in Info.plist `GoogleClientID` (and selamet/fislik-api#149 server side).
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static var clientID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?.nilIfBlank
    }

    func signIn() async throws -> String {
        guard let clientID = Self.clientID else { throw SocialAuthError.notConfigured }
        let scheme = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = scheme + ":/oauthredirect"
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cont.resume(throwing: SocialAuthError.cancelled) }
                else { cont.resume(throwing: SocialAuthError.failed) }
            }
            session.presentationContextProvider = self
            session.start()
        }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw SocialAuthError.failed
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "code": code, "client_id": clientID, "redirect_uri": redirect,
            "code_verifier": verifier, "grant_type": "authorization_code",
        ]
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let idToken = json["id_token"] as? String else {
            throw SocialAuthError.failed
        }
        return idToken
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.keyWindow ?? ASPresentationAnchor() }
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
}

/// "Apple ile devam et" / "Google ile devam et" buttons (2B full width, 2C half width).
struct SocialButtons: View {
    var compact = false
    var busy: Bool
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
        layout {
            Button(action: onApple) {
                HStack(spacing: compact ? 8 : 9) {
                    Icon(.apple, size: compact ? 17 : 19)
                    Text(compact ? "Apple" : "Apple ile devam et")
                }
            }
            .buttonStyle(.f(.dark, height: compact ? 46 : 50, fontSize: compact ? 14 : 15))

            Button(action: onGoogle) {
                HStack(spacing: compact ? 8 : 9) {
                    GoogleMark(size: compact ? 16 : 18)
                    Text(compact ? "Google" : "Google ile devam et")
                }
            }
            .buttonStyle(.f(.secondary, height: compact ? 46 : 50, fontSize: compact ? 14 : 15))
        }
        .disabled(busy)
    }
}

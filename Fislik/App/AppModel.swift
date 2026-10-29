import Foundation
import Observation
import SwiftUI

/// Thread-safe copy of the token for the networking layer.
final class TokenBox: @unchecked Sendable {
    static let shared = TokenBox()
    private let lock = NSLock()
    private var _value: String?

    var value: String? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Global session + navigation state.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case auth
        case locked          // Face ID gate
        case companySetup
        case main
    }

    enum DeepLink: Equatable {
        case invite(token: String)
        case passwordReset(token: String)
        case receipt(id: String, period: Period?)
        case camera
        case notifications
        case month(Period)
    }

    var phase: Phase = .launching
    var user: User?
    var sessionExpired = false
    var pendingLink: DeepLink?
    var unreadCount = 0

    @ObservationIgnored
    @AppStorage("onboardingDone") private var onboardingDone = false
    @ObservationIgnored
    @AppStorage("faceIDEnabled") var faceIDEnabled = false
    @ObservationIgnored
    @AppStorage("companySkipped") private var companySkipped = false

    private(set) var token: String? {
        didSet { TokenBox.shared.value = token }
    }

    init() {
        APIClient.shared.tokenProvider = { TokenBox.shared.value }
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.sessionExpired = true }
        }
    }

    var isAccountant: Bool { user?.role == .accountant }

    // MARK: Launch

    func start() async {
        if faceIDEnabled, Keychain.hasBiometricToken {
            phase = .locked
            return
        }
        if let stored = Keychain.token() {
            token = stored
            await restore()
        } else {
            phase = onboardingDone ? .auth : .onboarding
        }
    }

    func unlockWithFaceID() async {
        guard let stored = await Keychain.biometricToken(reason: "Fişlik'e giriş yap") else { return }
        token = stored
        await restore()
    }

    private func restore() async {
        do {
            user = try await API.me()
            await routeAfterLogin()
        } catch APIError.unauthorized, APIError.server(401, _) {
            signOutLocally()
        } catch {
            // Offline: keep the session and show cached data.
            user = SessionCache.user
            phase = user == nil ? .auth : .main
        }
    }

    func finishOnboarding() {
        onboardingDone = true
        phase = .auth
    }

    // MARK: Auth

    func signedIn(_ auth: AuthResponse) async {
        token = auth.accessToken
        Keychain.saveToken(auth.accessToken)
        if faceIDEnabled { _ = Keychain.saveBiometricToken(auth.accessToken) }
        user = auth.user
        sessionExpired = false
        onboardingDone = true
        await routeAfterLogin()
    }

    private func routeAfterLogin() async {
        SessionCache.user = user
        if user?.role == .client, !companySkipped, (try? await API.company()) == .some(nil) {
            phase = .companySetup
        } else {
            phase = .main
        }
    }

    func companyDone(skipped: Bool) {
        if skipped { companySkipped = true }
        phase = .main
    }

    func setFaceID(_ enabled: Bool) {
        faceIDEnabled = enabled
        if enabled, let token {
            faceIDEnabled = Keychain.saveBiometricToken(token)
        } else {
            Keychain.deleteBiometricToken()
        }
    }

    func signOut() async {
        if let deviceToken = PushManager.shared.deviceToken {
            try? await API.unregisterDevice(token: deviceToken)
        }
        signOutLocally()
    }

    func signOutLocally() {
        token = nil
        user = nil
        sessionExpired = false
        Keychain.clear()
        faceIDEnabled = false
        SessionCache.clear()
        ReceiptStore.shared.reset()
        NotificationsStore.shared.reset()
        UploadQueue.shared.clearAll()
        Task { await ReceiptImageLoader.shared.clear() }
        PushManager.shared.setBadge(0)
        phase = .auth
    }

    /// Push payload → deep link (`type` + string payload values).
    static func link(forNotification type: String, payload: [String: String]) -> DeepLink? {
        let period = payload["period"].flatMap(Period.init)
        switch type {
        case "issue_opened":
            return payload["receipt_id"].map { .receipt(id: $0, period: period) }
        case "receipts_processed", "period_locked":
            return period.map { .month($0) }
        case "uploads_finished":
            return .month(.current)
        default:
            return .notifications
        }
    }

    // MARK: Deep links

    func handle(url: URL) {
        guard let link = Self.parse(url) else { return }
        pendingLink = link
    }

    /// Accepts `https://fislik.selamet.dev/davet/{token}`, `/sifre-sifirla/{token}`, `/fis/{id}` and `fislik://…` equivalents.
    static func parse(_ url: URL) -> DeepLink? {
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "fislik", let host = url.host { parts.insert(host, at: 0) }
        guard let head = parts.first else { return nil }
        let arg = parts.count > 1 ? parts[1] : nil
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        switch head {
        case "davet": return arg.map { .invite(token: $0) }
        case "sifre-sifirla": return arg.map { .passwordReset(token: $0) }
        case "fis":
            let period = query?.first { $0.name == "period" }?.value.flatMap(Period.init)
            return arg.map { .receipt(id: $0, period: period) }
        case "kamera": return .camera
        case "bildirimler": return .notifications
        case "ay": return arg.flatMap(Period.init).map { .month($0) }
        default: return nil
        }
    }
}

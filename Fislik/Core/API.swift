import Foundation

/// Typed endpoints for fislik-api. One function per route.
enum API {
    private static var client: APIClient { .shared }

    // MARK: Auth

    struct RegisterBody: Encodable { let email, password, fullName: String; let role: UserRole; let inviteToken: String? }
    struct LoginBody: Encodable { let email, password: String }
    struct GoogleBody: Encodable { let credential: String }
    struct AppleBody: Encodable { let identityToken: String; let fullName: String? }
    struct OAuthRegisterBody: Encodable { let registrationToken: String; let role: UserRole }
    struct ChangePasswordBody: Encodable { let currentPassword, newPassword: String }
    struct EmailBody: Encodable { let email: String }
    struct ResetConfirmBody: Encodable { let token, newPassword: String }

    static func register(email: String, password: String, fullName: String, role: UserRole, inviteToken: String?) async throws -> AuthResponse {
        try await client.request(.post, "/auth/register", body: RegisterBody(email: email, password: password, fullName: fullName, role: role, inviteToken: inviteToken), authorized: false)
    }

    static func login(email: String, password: String) async throws -> AuthResponse {
        try await client.request(.post, "/auth/login", body: LoginBody(email: email, password: password), authorized: false)
    }

    static func google(idToken: String) async throws -> OAuthResult {
        try await client.request(.post, "/auth/oauth/google", body: GoogleBody(credential: idToken), authorized: false)
    }

    static func apple(identityToken: String, fullName: String?) async throws -> OAuthResult {
        try await client.request(.post, "/auth/oauth/apple", body: AppleBody(identityToken: identityToken, fullName: fullName), authorized: false)
    }

    static func oauthRegister(token: String, role: UserRole) async throws -> AuthResponse {
        try await client.request(.post, "/auth/oauth/register", body: OAuthRegisterBody(registrationToken: token, role: role), authorized: false)
    }

    static func me() async throws -> User {
        try await client.request(.get, "/auth/me")
    }

    static func deleteAccount() async throws {
        try await client.send(.delete, "/auth/me")
    }

    static func changePassword(current: String, new: String) async throws {
        try await client.send(.post, "/auth/change-password", body: ChangePasswordBody(currentPassword: current, newPassword: new))
    }

    static func requestPasswordReset(email: String) async throws {
        let _: EmptyResponse = try await client.request(.post, "/auth/password-reset/request", body: EmailBody(email: email), authorized: false)
    }

    static func confirmPasswordReset(token: String, newPassword: String) async throws {
        let _: EmptyResponse = try await client.request(.post, "/auth/password-reset/confirm", body: ResetConfirmBody(token: token, newPassword: newPassword), authorized: false)
    }

    // MARK: Receipts

    struct UploadBody: Encodable { let contentType: String; let period: String?; let clientId: String? }
    struct CompleteBody: Encodable { let sizeBytes: Int? }
    struct PeriodBody: Encodable { let period: String }
    struct MessageBody: Encodable { let message: String }

    static func receipts(_ period: Period) async throws -> [Receipt] {
        try await client.request(.get, "/receipts", query: ["period": period.raw])
    }

    static func createUpload(contentType: String, period: Period?, clientId: String?) async throws -> UploadTicket {
        try await client.request(.post, "/receipts/uploads", body: UploadBody(contentType: contentType, period: period?.raw, clientId: clientId))
    }

    static func completeUpload(receiptId: String, size: Int?) async throws -> Receipt {
        try await client.request(.post, "/receipts/\(receiptId)/complete", body: CompleteBody(sizeBytes: size))
    }

    static func moveReceipt(_ id: String, to period: Period) async throws -> Receipt {
        try await client.request(.patch, "/receipts/\(id)", body: PeriodBody(period: period.raw))
    }

    static func deleteReceipt(_ id: String) async throws {
        try await client.send(.delete, "/receipts/\(id)")
    }

    static func summary(_ period: Period, clientId: String? = nil) async throws -> MonthSummary {
        try await client.request(.get, "/receipts/summary", query: ["period": period.raw, "client_id": clientId])
    }

    static func patchExtraction(_ id: String, _ patch: ExtractionPatch) async throws -> Extraction {
        try await client.request(.patch, "/receipts/\(id)/extraction", body: patch)
    }

    static func retryExtraction(_ id: String) async throws -> Extraction {
        try await client.request(.post, "/receipts/\(id)/extraction/retry")
    }

    static func reanalyze(_ id: String) async throws -> Extraction {
        try await client.request(.post, "/receipts/\(id)/extraction/reanalyze")
    }

    static func periodLock(_ period: Period, clientId: String? = nil) async throws -> PeriodLock {
        do {
            return try await client.request(.get, "/receipts/period-lock", query: ["period": period.raw, "client_id": clientId])
        } catch APIError.server(404, _) {
            return PeriodLock(locked: false, lockedAt: nil)
        }
    }

    static func submission(_ period: Period) async throws -> SubmissionState {
        try await client.request(.get, "/receipts/submission", query: ["period": period.raw])
    }

    static func submit(_ period: Period) async throws -> SubmissionState {
        try await client.request(.post, "/receipts/submit", body: PeriodBody(period: period.raw))
    }

    // MARK: Issues

    static func openIssue(clientId: String, receiptId: String, message: String) async throws -> ReceiptIssue {
        try await client.request(.post, "/clients/\(clientId)/receipts/\(receiptId)/issues", body: MessageBody(message: message))
    }

    static func resolveIssue(_ id: String) async throws {
        try await client.send(.post, "/issues/\(id)/resolve")
    }

    // MARK: Grants

    static func grants() async throws -> [Grant] {
        try await client.request(.get, "/grants")
    }

    static func invite(email: String) async throws -> Grant {
        try await client.request(.post, "/grants", body: EmailBody(email: email))
    }

    static func acceptGrant(_ id: String) async throws -> Grant {
        try await client.request(.post, "/grants/\(id)/accept")
    }

    static func declineGrant(_ id: String) async throws {
        try await client.send(.post, "/grants/\(id)/decline")
    }

    static func revokeGrant(_ id: String) async throws {
        try await client.send(.delete, "/grants/\(id)")
    }

    static func invitePreview(token: String) async throws -> InvitePreview {
        try await client.request(.get, "/grants/invite/\(token)", authorized: false)
    }

    static func acceptInvite(token: String) async throws -> Grant {
        try await client.request(.post, "/grants/invite/\(token)/accept")
    }

    // MARK: Accountant

    static func clients(_ period: Period) async throws -> [ClientSummary] {
        try await client.request(.get, "/clients", query: ["period": period.raw])
    }

    static func clientReceipts(_ clientId: String, _ period: Period) async throws -> [Receipt] {
        try await client.request(.get, "/clients/\(clientId)/receipts", query: ["period": period.raw])
    }

    static func clientCompany(_ clientId: String) async throws -> CompanyProfile {
        try await client.request(.get, "/clients/\(clientId)/company")
    }

    static func setProcessed(clientId: String, receiptId: String, _ processed: Bool) async throws {
        try await client.send(processed ? .post : .delete, "/clients/\(clientId)/receipts/\(receiptId)/processed")
    }

    static func markMonthProcessed(clientId: String, _ period: Period) async throws -> CountResult {
        try await client.request(.post, "/clients/\(clientId)/receipts/processed", body: PeriodBody(period: period.raw))
    }

    static func unmarkMonthProcessed(clientId: String, _ period: Period) async throws -> CountResult {
        try await client.request(.delete, "/clients/\(clientId)/receipts/processed", query: ["period": period.raw])
    }

    static func downloadZip(clientId: String, _ period: Period, filename: String) async throws -> URL {
        try await client.download("/clients/\(clientId)/receipts.zip", query: ["period": period.raw], filename: filename)
    }

    static func lockPeriod(clientId: String, _ period: Period) async throws -> PeriodLock {
        try await client.request(.post, "/clients/\(clientId)/periods/\(period.raw)/lock")
    }

    static func unlockPeriod(clientId: String, _ period: Period) async throws {
        try await client.send(.delete, "/clients/\(clientId)/periods/\(period.raw)/lock")
    }

    // MARK: Company

    static func company() async throws -> CompanyProfile? {
        do {
            return try await client.request(.get, "/company")
        } catch APIError.server(404, _) {
            return nil
        }
    }

    static func saveCompany(_ profile: CompanyProfile) async throws -> CompanyProfile {
        try await client.request(.put, "/company", body: profile)
    }

    // MARK: Credits

    static func credits() async throws -> Credits {
        try await client.request(.get, "/credits/me")
    }

    // MARK: Notifications

    struct ReadBody: Encodable { let ids: [String]? }

    static func notifications(limit: Int = 50, offset: Int = 0) async throws -> NotificationPage {
        try await client.request(.get, "/notifications", query: ["limit": String(limit), "offset": String(offset)])
    }

    static func markRead(_ ids: [String]?) async throws {
        try await client.send(.post, "/notifications/read", body: ReadBody(ids: ids))
    }

    static func preferences() async throws -> NotificationPrefs {
        try await client.request(.get, "/notifications/preferences")
    }

    static func savePreferences(_ prefs: NotificationPrefs) async throws {
        try await client.send(.put, "/notifications/preferences", body: prefs)
    }

    // MARK: Devices (push)

    struct DeviceBody: Encodable { let token: String; let platform: String; let environment: String; let appVersion: String }

    /// APNs environment of this build: Xcode debug builds get sandbox tokens.
    static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    static func registerDevice(token: String) async throws {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        try await client.send(.post, "/devices", body: DeviceBody(token: token, platform: "ios", environment: apnsEnvironment, appVersion: version))
    }

    static func unregisterDevice(token: String) async throws {
        try await client.send(.delete, "/devices/\(token)")
    }
}

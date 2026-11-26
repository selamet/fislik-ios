import Foundation

/// Typed endpoints for fislik-api. One function per route.
enum API {
    private static var client: APIClient { .shared }

    // MARK: Auth

    struct RegisterBody: Encodable { let email, password, fullName: String; let role: UserRole; let inviteToken: String?; var memberInviteToken: String? = nil }
    struct LoginBody: Encodable { let email, password: String }
    struct GoogleBody: Encodable { let credential: String }
    struct AppleBody: Encodable { let identityToken: String; let authorizationCode: String?; let fullName: String? }
    struct OAuthRegisterBody: Encodable { let registrationToken: String; let role: UserRole; let authorizationCode: String?; var inviteToken: String? = nil; var memberInviteToken: String? = nil }
    struct ChangePasswordBody: Encodable { let currentPassword, newPassword: String }
    struct EmailBody: Encodable { let email: String }
    struct ResetConfirmBody: Encodable { let token, newPassword: String }
    struct VerifyEmailBody: Encodable { let code: String }

    static func register(email: String, password: String, fullName: String, role: UserRole, inviteToken: String?, memberInviteToken: String? = nil) async throws -> AuthResponse {
        try await client.request(.post, "/auth/register", body: RegisterBody(email: email, password: password, fullName: fullName, role: role, inviteToken: inviteToken, memberInviteToken: memberInviteToken), authorized: false)
    }

    static func login(email: String, password: String) async throws -> AuthResponse {
        try await client.request(.post, "/auth/login", body: LoginBody(email: email, password: password), authorized: false)
    }

    static func google(idToken: String) async throws -> OAuthResult {
        try await client.request(.post, "/auth/oauth/google", body: GoogleBody(credential: idToken), authorized: false)
    }

    static func apple(identityToken: String, authorizationCode: String?, fullName: String?) async throws -> OAuthResult {
        try await client.request(.post, "/auth/oauth/apple", body: AppleBody(identityToken: identityToken, authorizationCode: authorizationCode, fullName: fullName), authorized: false)
    }

    static func oauthRegister(token: String, role: UserRole, authorizationCode: String?, inviteToken: String? = nil, memberInviteToken: String? = nil) async throws -> AuthResponse {
        try await client.request(.post, "/auth/oauth/register", body: OAuthRegisterBody(registrationToken: token, role: role, authorizationCode: authorizationCode, inviteToken: inviteToken, memberInviteToken: memberInviteToken), authorized: false)
    }

    // MARK: Invite links of either kind

    static func invite(token: String) async throws -> InviteLookup {
        try await client.request(.get, "/invites/\(token)", authorized: false)
    }

    /// `companyId` picks the company a client links an accountant to.
    static func acceptInvite(token: String, companyId: String?) async throws -> JoinedViaInvite {
        try await APIClient.$pinnedCompanyId.withValue(companyId) {
            try await client.request(.post, "/invites/\(token)/accept")
        }
    }

    static func declineInvite(token: String) async throws {
        try await client.send(.post, "/invites/\(token)/decline")
    }

    static func me() async throws -> User {
        try await client.request(.get, "/auth/me")
    }

    static func verifyEmail(code: String) async throws -> User {
        try await client.request(.post, "/auth/email/verify", body: VerifyEmailBody(code: code))
    }

    static func resendEmailCode() async throws {
        try await client.send(.post, "/auth/email/resend")
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

    /// Spending report of the active company for one month.
    static func monthlyReport(_ period: Period) async throws -> MonthlyReport {
        try await client.request(.get, "/reports/monthly", query: ["period": period.raw])
    }

    // MARK: Manual expenses

    static func expenses(_ period: Period) async throws -> [Expense] {
        try await client.request(.get, "/expenses", query: ["period": period.raw])
    }

    static func createExpense(_ body: ExpenseBody) async throws -> Expense {
        try await client.request(.post, "/expenses", body: body)
    }

    static func updateExpense(_ id: String, _ body: ExpenseBody) async throws -> Expense {
        try await client.request(.patch, "/expenses/\(id)", body: body)
    }

    static func deleteExpense(_ id: String) async throws {
        try await client.send(.delete, "/expenses/\(id)")
    }

    // MARK: Recurring expenses

    static func recurringExpenses() async throws -> [RecurringExpense] {
        try await client.request(.get, "/expenses/recurring")
    }

    static func createRecurringExpense(_ body: RecurringBody) async throws -> RecurringExpense {
        try await client.request(.post, "/expenses/recurring", body: body)
    }

    static func updateRecurringExpense(_ id: String, _ body: RecurringBody) async throws -> RecurringExpense {
        try await client.request(.patch, "/expenses/recurring/\(id)", body: body)
    }

    static func setRecurringExpenseActive(_ id: String, _ active: Bool) async throws -> RecurringExpense {
        try await client.request(.patch, "/expenses/recurring/\(id)", body: RecurringActiveBody(active: active))
    }

    static func deleteRecurringExpense(_ id: String) async throws {
        try await client.send(.delete, "/expenses/recurring/\(id)")
    }

    // MARK: Detected subscriptions

    static func subscriptions() async throws -> DetectedSubscriptions {
        try await client.request(.get, "/reports/subscriptions")
    }

    static func trackSubscription(_ id: String) async throws {
        let _: TrackSubscriptionReply = try await client.request(.post, "/reports/subscriptions/\(id)/track", body: TrackSubscriptionBody())
    }

    static func dismissSubscription(_ id: String) async throws {
        try await client.send(.post, "/reports/subscriptions/\(id)/dismiss")
    }

    static func restoreDismissedSubscriptions() async throws {
        try await client.send(.delete, "/reports/subscriptions/dismissed")
    }

    // MARK: Statements

    static func statements() async throws -> [Statement] {
        try await client.request(.get, "/statements")
    }

    static func statement(_ id: String) async throws -> Statement {
        try await client.request(.get, "/statements/\(id)")
    }

    static func uploadStatement(fileName: String, data: Data) async throws -> Statement {
        try await client.upload("/statements", field: "file", fileName: fileName,
                                mimeType: StatementFiles.mimeType(for: fileName), data: data)
    }

    static func deleteStatement(_ id: String) async throws {
        try await client.send(.delete, "/statements/\(id)")
    }

    static func expenseFromStatementLine(_ statementId: String, _ lineId: String, category: String, description: String?) async throws -> Statement {
        try await client.request(.post, "/statements/\(statementId)/lines/\(lineId)/expense",
                                 body: LineExpenseBody(category: category, description: description))
    }

    static func setStatementLineIgnored(_ statementId: String, _ lineId: String, ignored: Bool) async throws -> Statement {
        try await client.request(.patch, "/statements/\(statementId)/lines/\(lineId)", body: LineIgnoreBody(ignored: ignored))
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

    static func acceptGrant(_ id: String, companyId: String? = nil) async throws -> Grant {
        try await APIClient.$pinnedCompanyId.withValue(companyId) {
            try await client.request(.post, "/grants/\(id)/accept")
        }
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

    // MARK: Companies

    struct CompanyNameBody: Encodable { let name: String }

    static func companies() async throws -> [CompanyMembership] {
        try await client.request(.get, "/companies")
    }

    static func createCompany(name: String) async throws -> CompanyMembership {
        try await client.request(.post, "/companies", body: CompanyNameBody(name: name))
    }

    // MARK: Members

    struct MemberInviteBody: Encodable { let email: String; let role: MemberRole }
    struct MemberRoleBody: Encodable { let role: MemberRole }

    static func members(_ companyId: String) async throws -> [CompanyMember] {
        try await client.request(.get, "/companies/\(companyId)/members")
    }

    static func inviteMember(_ companyId: String, email: String, role: MemberRole) async throws -> CompanyMember {
        try await client.request(.post, "/companies/\(companyId)/members", body: MemberInviteBody(email: email, role: role))
    }

    static func resendMemberInvite(_ companyId: String, memberId: String) async throws {
        try await client.send(.post, "/companies/\(companyId)/members/\(memberId)/resend")
    }

    static func changeMemberRole(_ companyId: String, memberId: String, role: MemberRole) async throws -> CompanyMember {
        try await client.request(.patch, "/companies/\(companyId)/members/\(memberId)", body: MemberRoleBody(role: role))
    }

    static func removeMember(_ companyId: String, memberId: String) async throws {
        try await client.send(.delete, "/companies/\(companyId)/members/\(memberId)")
    }

    static func memberInvites() async throws -> [MemberInvite] {
        try await client.request(.get, "/memberships/invites")
    }

    static func acceptMemberInvite(id: String) async throws -> CompanyMembership {
        try await client.request(.post, "/memberships/\(id)/accept")
    }

    static func declineMemberInvite(id: String) async throws {
        try await client.send(.post, "/memberships/\(id)/decline")
    }

    static func memberInviteInfo(token: String) async throws -> MemberInviteInfo {
        try await client.request(.get, "/memberships/invite/\(token)", authorized: false)
    }

    static func acceptMemberInvite(token: String) async throws -> CompanyMembership {
        try await client.request(.post, "/memberships/invite/\(token)/accept")
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

    // MARK: Billing

    static func plans() async throws -> [Plan] {
        try await client.request(.get, "/plans")
    }

    static func billing() async throws -> Billing {
        try await client.request(.get, "/billing/me")
    }

    struct AppStoreTransactionBody: Encodable { let signedTransaction: String }

    /// Attaches a StoreKit 2 signed transaction to the active company.
    static func attachAppStoreTransaction(_ signedTransaction: String) async throws -> CompanySubscription {
        try await client.request(.post, "/billing/app-store/transactions", body: AppStoreTransactionBody(signedTransaction: signedTransaction))
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

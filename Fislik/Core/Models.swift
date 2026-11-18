import Foundation

// Models mirror fislik-api response schemas (see docs/api-contract.md).

enum UserRole: String, Codable, CaseIterable {
    case client, accountant, admin
}

struct User: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let fullName: String
    let role: UserRole
    var impersonated: Bool = false

    var initials: String { fullName.initials }
}

struct AuthResponse: Codable {
    let id: String
    let email: String
    let fullName: String
    let role: UserRole
    let accessToken: String

    var user: User { User(id: id, email: email, fullName: fullName, role: role) }
}

struct OAuthResult: Codable {
    enum Status: String, Codable { case loggedIn = "logged_in", needsRole = "needs_role" }
    let status: Status
    let user: AuthResponse?
    let registrationToken: String?
}

// MARK: - Receipts

enum DocType: String, Codable, CaseIterable {
    case fis, fatura, unknown

    var label: String {
        switch self {
        case .fis: "Fiş"
        case .fatura: "Fatura"
        case .unknown: "Bilinmiyor"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable {
    case nakit
    case krediKarti = "kredi_karti"
    case bilinmiyor

    var label: String {
        switch self {
        case .nakit: "Nakit"
        case .krediKarti: "Kredi Kartı"
        case .bilinmiyor: "Bilinmiyor"
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable {
    case market, yakit, yemek, ofis, iletisim, ulasim, konaklama, teknoloji, saglik, diger

    var label: String {
        switch self {
        case .yemek: "Yemek"
        case .market: "Market"
        case .yakit: "Yakıt"
        case .ulasim: "Ulaşım"
        case .konaklama: "Konaklama"
        case .ofis: "Ofis"
        case .teknoloji: "Teknoloji"
        case .iletisim: "İletişim"
        case .saglik: "Sağlık"
        case .diger: "Diğer"
        }
    }
}

enum TaxIdType: String, Codable {
    case vkn, tckn
}

struct VatLine: Codable, Hashable {
    var rate: Int
    var amount: Decimal
}

struct Extraction: Codable, Equatable {
    enum Status: String, Codable { case pending, done, failed }

    var status: Status
    var merchantName: String?
    var merchantLegalName: String?
    var receiptDate: Date?
    var totalAmount: Decimal?
    var vatTotal: Decimal?
    var vatBreakdown: [VatLine]
    var docType: DocType?
    var merchantTaxId: String?
    var merchantTaxIdType: TaxIdType?
    var merchantTaxOffice: String?
    var receiptNumber: String?
    var paymentMethod: PaymentMethod?
    var expenseCategory: ExpenseCategory?
    var edited: Bool
}

struct ReceiptIssue: Codable, Equatable, Identifiable {
    let id: String
    let message: String
    let authorName: String?
    let createdAt: Date
}

struct Receipt: Codable, Equatable, Identifiable {
    let id: String
    var period: String
    let createdAt: Date
    let imageUrl: URL?
    let contentType: String
    var processed: Bool
    var openIssue: ReceiptIssue?
    var extraction: Extraction?
    let uploadedBy: String?

    var isPDF: Bool { contentType == "application/pdf" }
}

struct UploadTicket: Codable {
    let receiptId: String
    let objectKey: String
    let uploadUrl: URL
}

struct MonthSummary: Codable, Equatable {
    var receiptCount: Int
    var analyzedCount: Int
    var totalAmount: Decimal
    var vatTotal: Decimal
    var vatByRate: [String: Decimal]
    var paymentMethodTotals: [String: Decimal]
    var categoryTotals: [String: Decimal]

    static let empty = MonthSummary(receiptCount: 0, analyzedCount: 0, totalAmount: 0, vatTotal: 0, vatByRate: [:], paymentMethodTotals: [:], categoryTotals: [:])
}

struct PeriodLock: Codable, Equatable {
    var locked: Bool
    var lockedAt: Date?
}

struct SubmissionState: Codable, Equatable {
    var lastSentAt: Date?
    var canSend: Bool
    var activeReceiptCount: Int
    var hasAccountant: Bool
}

/// Partial update for `PATCH /receipts/{id}/extraction`; nil fields are omitted, `.some(nil)` clears.
struct ExtractionPatch: Encodable {
    var merchantName: String??
    var merchantLegalName: String??
    var receiptDate: String??
    var totalAmount: Decimal??
    var vatTotal: Decimal??
    var vatBreakdown: [VatLine]?
    var docType: DocType??
    var merchantTaxId: String??
    var merchantTaxIdType: TaxIdType??
    var merchantTaxOffice: String??
    var receiptNumber: String??
    var paymentMethod: PaymentMethod??
    var expenseCategory: ExpenseCategory??

    enum CodingKeys: String, CodingKey {
        case merchantName, merchantLegalName, receiptDate, totalAmount, vatTotal, vatBreakdown, docType
        case merchantTaxId, merchantTaxIdType, merchantTaxOffice, receiptNumber, paymentMethod, expenseCategory
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func put<T: Encodable>(_ value: T??, _ key: CodingKeys) throws {
            guard let value else { return }
            if let inner = value { try c.encode(inner, forKey: key) } else { try c.encodeNil(forKey: key) }
        }
        try put(merchantName, .merchantName)
        try put(merchantLegalName, .merchantLegalName)
        try put(receiptDate, .receiptDate)
        try put(totalAmount, .totalAmount)
        try put(vatTotal, .vatTotal)
        if let vatBreakdown { try c.encode(vatBreakdown, forKey: .vatBreakdown) }
        try put(docType, .docType)
        try put(merchantTaxId, .merchantTaxId)
        try put(merchantTaxIdType, .merchantTaxIdType)
        try put(merchantTaxOffice, .merchantTaxOffice)
        try put(receiptNumber, .receiptNumber)
        try put(paymentMethod, .paymentMethod)
        try put(expenseCategory, .expenseCategory)
    }
}

// MARK: - Grants

struct Grant: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case pending, active, revoked }
    enum Direction: String, Codable { case incoming, outgoing }

    let id: String
    var status: Status
    let invitedEmail: String
    let direction: Direction
    let counterpartName: String?
    let counterpartEmail: String?
    let invitedRole: UserRole?

    var displayName: String { counterpartName ?? counterpartEmail ?? invitedEmail }
    var displayEmail: String { counterpartEmail ?? invitedEmail }
}

struct InvitePreview: Codable, Equatable {
    let invitedEmail: String
    let inviterName: String?
    let inviterRole: UserRole?
    let invitedRole: UserRole?
}

// MARK: - Accountant

struct ClientSummary: Codable, Equatable, Identifiable {
    let clientId: String
    let fullName: String
    let receiptCount: Int
    let unprocessedCount: Int
    let lastUploadAt: Date?

    var id: String { clientId }
}

struct CountResult: Codable {
    var marked: Int?
    var unmarked: Int?
}

// MARK: - Company

struct CompanyProfile: Codable, Equatable {
    var fullName: String
    var tradeName: String?
    var taxOffice: String
    var taxNumber: String
    var nationalId: String?
    var businessAddress: String
    var taxType: String?
    var activityCode: String?
    var activityName: String?
    var startedOn: String?
}

// MARK: - Credits

struct Credits: Codable, Equatable {
    var limit: Int?
    var used: Int
    var remaining: Int?
    var unlimited: Bool

    var exhausted: Bool { !unlimited && (remaining ?? 1) <= 0 }

    enum LimitState: Equatable { case ok, near, full }

    /// Where the pool stands against its monthly limit. "near" starts when
    /// 2 receipts or 20 % of the limit are left, whichever is larger — the
    /// same rule the web app uses.
    var limitState: LimitState {
        guard !unlimited, let limit, let remaining else { return .ok }
        if remaining <= 0 { return .full }
        return remaining <= max(2, limit / 5) ? .near : .ok
    }
}

// MARK: - Notifications

struct AppNotification: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let payload: [String: JSONValue]
    var read: Bool
    let createdAt: Date
}

struct NotificationPage: Codable {
    let unreadCount: Int
    let items: [AppNotification]
}

/// Minimal JSON value for free-form notification payloads.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        default: nil
        }
    }

    var int: Int? {
        switch self {
        case .number(let n): Int(n)
        case .string(let s): Int(s)
        default: nil
        }
    }
}

// MARK: - Companies

/// A user's role inside one company (membership), not the account type.
enum MemberRole: String, Codable, CaseIterable {
    case owner, admin, uploader

    var label: String {
        switch self {
        case .owner: "Sahip"
        case .admin: "Yönetici"
        case .uploader: "Yükleyici"
        }
    }

    var isManager: Bool { self != .uploader }
}

/// One of the caller's active company memberships (`GET /companies`).
struct CompanyMembership: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let role: MemberRole
    /// Active member count; optional so older API responses still decode.
    var memberCount: Int?

    var initials: String { name.initials }

    /// "Sahip · 3 üye", or just the role for a one-person company.
    var caption: String {
        guard let memberCount, memberCount > 1 else { return role.label }
        return "\(role.label) · \(memberCount) üye"
    }
}

/// A company member or pending invite (`GET /companies/{id}/members`).
struct CompanyMember: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case active, pending }

    let id: String
    let userId: String?
    let fullName: String?
    let email: String
    var role: MemberRole
    let status: Status
    let isMe: Bool
    let receiptsThisMonth: Int
    let joinedAt: Date?
    let invitedAt: Date

    var isPending: Bool { status == .pending }
    var displayName: String { fullName ?? email }

    /// Owners manage everyone but themselves; admins manage uploaders and
    /// pending invites (mirrors the API, which stays authoritative).
    func manageable(by viewer: MemberRole) -> Bool {
        if isMe || role == .owner { return false }
        if viewer == .owner { return true }
        return viewer == .admin && (isPending || role == .uploader)
    }
}

/// A pending member invite seen by the invitee (`GET /memberships/invites`).
struct MemberInvite: Codable, Equatable, Identifiable {
    let id: String
    let companyId: String
    let companyName: String
    let role: MemberRole
    let inviterName: String?
    let createdAt: Date
}

/// Public preview of an invite link (`GET /memberships/invite/{token}`).
struct MemberInviteInfo: Codable, Equatable {
    let companyName: String
    let role: MemberRole
    let inviterName: String?
    let email: String
    let accountExists: Bool
}

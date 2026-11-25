import Foundation
import Observation

/// The caller's company memberships and the active one.
///
/// The active id is persisted in `UserDefaults` (thread-safe, so the
/// networking layer reads it directly for `X-Company-Id`). A stored id that
/// is no longer one of the memberships falls back to the first membership.
/// When `GET /companies` isn't available (older API) the list stays empty,
/// no header is sent and the app behaves exactly as before.
@MainActor
@Observable
final class CompanyStore {
    static let shared = CompanyStore()

    nonisolated static let activeKey = "activeCompanyId"

    private(set) var companies: [CompanyMembership] = []
    /// Pending member invites addressed to the signed-in client.
    private(set) var invites: [MemberInvite] = []
    private(set) var activeId: String? = UserDefaults.standard.string(forKey: activeKey)

    var active: CompanyMembership? { companies.first { $0.id == activeId } }
    /// True once the list has actually loaded (a failed load keeps it false).
    private(set) var loaded = false

    /// A client with no company at all: they left (or were removed from) the
    /// only team they had joined through an invite.
    var hasNoCompany: Bool { Self.showsNoCompany(loaded: loaded, companies: companies) }

    nonisolated static func showsNoCompany(loaded: Bool, companies: [CompanyMembership]) -> Bool {
        loaded && companies.isEmpty
    }

    /// Read by `APIClient` on any thread.
    nonisolated static func storedActiveId() -> String? {
        UserDefaults.standard.string(forKey: activeKey)
    }

    func load() async {
        guard let list = try? await API.companies() else { return }
        companies = list
        loaded = true
        if !list.contains(where: { $0.id == activeId }) {
            setActive(list.first?.id)
        }
    }

    /// Switches the tenant: persists the id and drops everything cached for
    /// the previous company. Pending uploads keep their own company id.
    func select(_ id: String) {
        guard id != activeId, companies.contains(where: { $0.id == id }) else { return }
        setActive(id)
        ReceiptStore.shared.reset()
        BillingStore.shared.reset()
    }

    /// Creates a company (caller becomes owner) and switches to it.
    func create(name: String) async throws {
        let company = try await API.createCompany(name: name)
        companies.append(company)
        select(company.id)
    }

    func loadInvites() async {
        invites = (try? await API.memberInvites()) ?? []
    }

    /// Joins a company (in-app invite or link token) and switches to it.
    func accept(inviteId: String? = nil, token: String? = nil) async throws {
        let company: CompanyMembership
        if let inviteId {
            company = try await API.acceptMemberInvite(id: inviteId)
        } else if let token {
            company = try await API.acceptMemberInvite(token: token)
        } else {
            return
        }
        invites.removeAll { $0.id == inviteId || $0.companyId == company.id }
        await load()
        select(company.id)
    }

    func decline(inviteId: String) async throws {
        try await API.declineMemberInvite(id: inviteId)
        invites.removeAll { $0.id == inviteId }
    }

    func reset() {
        loaded = false
        companies = []
        invites = []
        setActive(nil)
    }

    private func setActive(_ id: String?) {
        activeId = id
        if let id {
            UserDefaults.standard.set(id, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }
}

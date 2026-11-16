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
    private(set) var activeId: String? = UserDefaults.standard.string(forKey: activeKey)

    var active: CompanyMembership? { companies.first { $0.id == activeId } }

    /// Read by `APIClient` on any thread.
    nonisolated static func storedActiveId() -> String? {
        UserDefaults.standard.string(forKey: activeKey)
    }

    func load() async {
        guard let list = try? await API.companies() else { return }
        companies = list
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
    }

    /// Creates a company (caller becomes owner) and switches to it.
    func create(name: String) async throws {
        let company = try await API.createCompany(name: name)
        companies.append(company)
        select(company.id)
    }

    func reset() {
        companies = []
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

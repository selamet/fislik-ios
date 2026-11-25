import SwiftUI

/// What an invite notification can act on.
struct InviteAction: Equatable {
    let kind: InviteKind
    /// Membership id (member invites) or grant id (grants).
    let id: String
    /// The server's view: "pending", "accepted" or "closed".
    let status: String
    /// The account role the invite is for.
    let invitedRole: UserRole?
    let inviterName: String?
}

/// Inline "Kabul et / Reddet" under an invite notification. After an action
/// the local outcome is shown; otherwise the server's status decides.
struct InviteActionsRow: View {
    enum Local: Equatable { case accepted, declined, gone }
    enum State: Equatable {
        case open, accepted, declined, gone

        init(status: String, local: Local?) {
            switch local {
            case .accepted?: self = .accepted
            case .declined?: self = .declined
            case .gone?: self = .gone
            case nil:
                switch status {
                case "pending": self = .open
                case "accepted": self = .accepted
                default: self = .gone
                }
            }
        }
    }

    let action: InviteAction
    @Environment(AppModel.self) private var app
    @SwiftUI.State private var local: Local?
    @SwiftUI.State private var busy = false
    @SwiftUI.State private var error: String?
    @SwiftUI.State private var picking: [CompanyMembership] = []

    var body: some View {
        let state = State(status: action.status, local: local)
        Group {
            switch state {
            case .open:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        FMiniButton(title: "Kabul et", icon: .check, color: FColor.brand, height: 30) { Task { await accept() } }
                        FMiniButton(title: "Reddet", height: 30) { Task { await decline() } }
                    }
                    .disabled(busy)
                    if let error { Text(error).fFont(11.5, .semibold).foregroundStyle(FColor.danger) }
                }
            case .accepted:
                label(action.kind == .member ? "Katıldın" : "Kabul edildi", icon: .check)
            case .declined:
                label("Reddedildi", icon: .x)
            case .gone:
                label("Davet artık geçerli değil", icon: .x)
            }
        }
        .padding(.top, 4)
        .confirmationDialog("Hangi şirket için?", isPresented: Binding(get: { !picking.isEmpty }, set: { if !$0 { picking = [] } }), titleVisibility: .visible) {
            ForEach(picking) { company in
                Button(company.name) { Task { await acceptGrant(companyId: company.id) } }
            }
        }
    }

    private func label(_ text: String, icon: FIcon) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 13)
            Text(text)
        }
        .fFont(11.5, .bold)
        .foregroundStyle(FColor.muted)
    }

    private func accept() async {
        if action.kind == .member {
            await run {
                let company = try await API.acceptMemberInvite(id: action.id)
                local = .accepted
                await app.didJoin(JoinedViaInvite(kind: .member, companyId: company.id, companyName: company.name, role: company.role.rawValue, inviterName: action.inviterName))
            }
        } else if action.invitedRole == .client {
            await CompanyStore.shared.load()
            let managed = CompanyStore.shared.companies.filter { $0.role != .uploader }
            if managed.count > 1 { picking = managed } else { await acceptGrant(companyId: managed.first?.id) }
        } else {
            await acceptGrant(companyId: nil)
        }
    }

    private func acceptGrant(companyId: String?) async {
        await run {
            _ = try await API.acceptGrant(action.id, companyId: companyId)
            local = .accepted
            await ReceiptStore.shared.refreshGrants()
        }
    }

    private func decline() async {
        await run {
            if action.kind == .member {
                try await API.declineMemberInvite(id: action.id)
            } else {
                try await API.declineGrant(action.id)
            }
            local = .declined
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
            await CompanyStore.shared.loadInvites()
        } catch let e as APIError where e.status == 404 || e.status == 409 {
            local = .gone
        } catch let e as APIError {
            error = e.status == 403 ? "Bu daveti yalnızca şirketin sahibi ya da yöneticisi kabul edebilir." : e.message
        } catch {
            self.error = APIError.transport(code: 0).message
        }
    }
}

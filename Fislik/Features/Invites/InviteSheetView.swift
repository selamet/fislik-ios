import SwiftUI

/// An invite link token presented as a sheet.
struct InviteLinkToken: Identifiable, Equatable {
    let token: String
    var id: String { token }
}

/// An invite link opened while signed in (either kind): accept or decline
/// it, or — when it was meant for another account or role — sign out and
/// continue on the landing as the invited account.
struct InviteSheetView: View {
    let token: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var info: InviteLookup?
    @State private var loadError: String?
    @State private var busy = false
    @State private var error: String?
    @State private var declined = false
    @State private var picking: [CompanyMembership] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.x, size: 22).foregroundStyle(FColor.ink).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kapat")
                Spacer()
            }
            .padding(.horizontal, 12)
            ScrollView {
                Group {
                    if declined {
                        InviteCard { Text("Daveti reddettin").fFont(19, .heavy) }
                    } else if let info {
                        content(info)
                    } else if let loadError {
                        FBanner(icon: .circleAlert, tone: .danger, text: Text(loadError))
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding(20)
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .task { await load() }
        .confirmationDialog("Hangi şirket için?", isPresented: Binding(get: { !picking.isEmpty }, set: { if !$0 { picking = [] } }), titleVisibility: .visible) {
            ForEach(picking) { company in
                Button(company.name) { Task { await accept(companyId: company.id) } }
            }
        } message: {
            Text("Muhasebecin bu şirketin fişlerini görebilecek.")
        }
    }

    private func content(_ info: InviteLookup) -> some View {
        let user = app.user
        let eligible = user?.role == info.invitedAccountRole
        let sameEmail = user?.email.lowercased() == info.email.lowercased()
        // Member invites may be accepted under another address; grants only by the invited one.
        let canAccept = eligible && (sameEmail || info.kind == .member)
        return InviteCard {
            InviteSummary(info: info)
            Group {
                if !eligible {
                    Text(info.kind == .member
                         ? "Ekip davetleri mükellef hesapları içindir; şu an muhasebeci hesabıyla giriş yapmış durumdasın."
                         : "Bu davet bir \(InviteCopy.accountRoleLabel(info.invitedAccountRole)) hesabı içindir; şu an \(InviteCopy.accountRoleLabel(user?.role ?? .client)) hesabıyla giriş yapmış durumdasın.")
                } else if !sameEmail {
                    Text("Bu davet \(info.email) adresine gönderildi, sen \(user?.email ?? "") olarak giriş yaptın.")
                }
            }
            .fFont(13, .medium)
            .foregroundStyle(FColor.muted)
            .multilineTextAlignment(.center)

            AuthErrorText(error: error)

            if canAccept {
                Button { Task { await startAccept(info) } } label: {
                    FButtonLabel(title: sameEmail ? "Daveti kabul et" : "Yine de kabul et", loading: busy)
                }
                .buttonStyle(.fPrimary)
                .disabled(busy)
            }
            if canAccept && sameEmail {
                Button { Task { await decline() } } label: { FButtonLabel(title: "Reddet") }
                    .buttonStyle(.fSecondary)
                    .disabled(busy)
            }
            if !eligible || !sameEmail {
                Button { Task { await signOutAndContinue(info) } } label: { FButtonLabel(title: "Çıkış yap ve devam et") }
                    .buttonStyle(.fSecondary)
            }
        }
    }

    private func load() async {
        do {
            info = try await API.invite(token: token)
        } catch let e as APIError {
            loadError = e.status == 404 ? "Bu davet bulunamadı ya da daha önce kullanılmış." : e.message
        } catch {
            loadError = APIError.transport(code: 0).message
        }
    }

    private func startAccept(_ info: InviteLookup) async {
        guard info.kind == .grant, info.invitedAccountRole == .client else {
            await accept(companyId: nil)
            return
        }
        await CompanyStore.shared.load()
        let managed = CompanyStore.shared.companies.filter { $0.role != .uploader }
        if managed.count > 1 {
            picking = managed
        } else {
            await accept(companyId: managed.first?.id)
        }
    }

    private func accept(companyId: String?) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let joined = try await API.acceptInvite(token: token, companyId: companyId)
            dismiss()
            await app.didJoin(joined)
        } catch let e as APIError {
            error = switch e.status {
            case 403: "Bu daveti yalnızca şirketin sahibi ya da yöneticisi kabul edebilir."
            case 404: InviteCopy.gone
            case 409: "Zaten bu şirketin ekibindesin."
            default: e.message
            }
        } catch {
            self.error = APIError.transport(code: 0).message
        }
    }

    private func decline() async {
        busy = true
        defer { busy = false }
        do {
            try await API.declineInvite(token: token)
            declined = true
            await CompanyStore.shared.loadInvites()
        } catch let e as APIError {
            error = e.status == 404 ? InviteCopy.gone : e.message
        } catch {
            self.error = APIError.transport(code: 0).message
        }
    }

    /// Signs out and reopens this invite on the landing, as the invited account.
    private func signOutAndContinue(_ info: InviteLookup) async {
        dismiss()
        await app.signOut()
        app.pendingLink = info.kind == .member ? .memberInvite(token: token) : .invite(token: token)
        app.phase = .auth
    }
}

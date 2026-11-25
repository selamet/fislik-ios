import SwiftUI

/// Shown to a client with no company at all: start their own, or accept a
/// pending team invite (listed below, from the in-app invites).
struct NoCompanyView: View {
    @Environment(AppModel.self) private var app
    @State private var companies = CompanyStore.shared
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Icon(.building, size: 26)
                        .foregroundStyle(FColor.brand)
                        .frame(width: 62, height: 62)
                        .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                    Text("Şu an bir şirkette değilsin").fFont(20, .heavy).accessibilityAddTraits(.isHeader)
                    Text("Kendi şirketini oluşturabilir ya da bir ekip davetini kabul edebilirsin. Bir davet bekliyorsan e-postanı kontrol et.")
                        .fFont(13.5, .medium)
                        .foregroundStyle(FColor.muted)
                        .multilineTextAlignment(.center)
                    AuthErrorText(error: error)
                    Button { Task { await create() } } label: {
                        FButtonLabel(title: "Kendi şirketimi oluştur", loading: busy)
                    }
                    .buttonStyle(.fPrimary)
                    .disabled(busy)
                }
                .padding(20)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                ForEach(companies.invites) { invite in
                    HStack(spacing: 12) {
                        FAvatar(initials: invite.companyName.initials, size: 42)
                        Text("\(invite.companyName) ekibine davet edildin").fFont(13.5, .bold)
                        Spacer(minLength: 0)
                        FMiniButton(title: "Katıl", color: FColor.brand, height: 30) {
                            Task {
                                do {
                                    try await companies.accept(inviteId: invite.id)
                                    await app.didJoin(JoinedViaInvite(kind: .member, companyId: invite.companyId, companyName: invite.companyName, role: invite.role.rawValue, inviterName: invite.inviterName))
                                } catch {
                                    self.error = (error as? APIError)?.status == 404 ? InviteCopy.gone : APIError.transport(code: 0).message
                                    await companies.loadInvites()
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(FColor.card, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
        }
        .background(FColor.bg.ignoresSafeArea())
        .task { await companies.loadInvites() }
    }

    private func create() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await companies.create(name: app.user?.fullName ?? "Şirketim")
            app.phase = .companySetup
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = APIError.transport(code: 0).message
        }
    }
}

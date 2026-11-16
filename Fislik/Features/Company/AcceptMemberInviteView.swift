import SwiftUI

/// Member invite acceptance (design `04-accept-invite`), opened from a
/// universal link (`/uye-davet/{token}`), a `member_invite` push or the
/// in-app invites banner. Accepting joins the company and switches to it.
struct AcceptMemberInviteView: View {
    enum Source: Equatable, Identifiable {
        case token(String)
        case invite(MemberInvite)

        var id: String {
            switch self {
            case .token(let t): "token-\(t)"
            case .invite(let i): "invite-\(i.id)"
            }
        }
    }

    let source: Source
    @Environment(\.dismiss) private var dismiss
    @State private var companies = CompanyStore.shared
    @State private var info: (company: String, inviter: String?, role: MemberRole)?
    @State private var loadError: String?
    @State private var busy = false
    @State private var error: String?

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

            if let info {
                content(info)
            } else if let loadError {
                Spacer()
                FBanner(icon: .circleAlert, tone: .danger, text: Text(loadError)).padding(24)
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .task { await loadInfo() }
    }

    private func content(_ info: (company: String, inviter: String?, role: MemberRole)) -> some View {
        VStack(spacing: 22) {
            ZStack(alignment: .bottomTrailing) {
                FAvatar(initials: info.company.initials, size: 96, radius: 30)
                Icon(.camera, size: 17)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(FColor.brand, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(FColor.bg, lineWidth: 3))
                    .offset(x: 6, y: 6)
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("EKİP DAVETİ").fFont(12, .heavy, tracking: 0.5).foregroundStyle(FColor.brand)
                Text("\(info.inviter ?? info.company) seni ekibine davet etti")
                    .fFont(26, .heavy, tracking: -0.8)
                    .multilineTextAlignment(.center)
                Text("Kabul edersen bu şirket adına fiş yükleyebilirsin. Kendi hesabın ve diğer şirketlerin etkilenmez.")
                    .fFont(14, .medium)
                    .foregroundStyle(FColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                infoRow("Şirket", info.company)
                RowDivider()
                infoRow("Rolün", info.role.label)
                RowDivider()
                infoRow("Analiz kredisi", "Şirket öder")
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .fCard(radius: 18)

            if let error {
                FBanner(icon: .circleAlert, tone: .danger, text: Text(error))
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: accept) { FButtonLabel(title: "Daveti kabul et", loading: busy) }
                    .buttonStyle(.f(.primary, height: 52))
                    .fBrandShadow()
                    .disabled(busy)
                Button("Reddet", action: decline)
                    .buttonStyle(.f(.secondary, height: 50, fontSize: 14))
                    .disabled(busy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).fFont(13, .semibold).foregroundStyle(FColor.muted)
            Spacer()
            Text(value).fFont(13, .heavy).foregroundStyle(FColor.ink)
        }
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func loadInfo() async {
        switch source {
        case .invite(let invite):
            info = (invite.companyName, invite.inviterName, invite.role)
        case .token(let token):
            do {
                let preview = try await API.memberInviteInfo(token: token)
                info = (preview.companyName, preview.inviterName, preview.role)
            } catch let e as APIError {
                loadError = e.status == 404 ? "Bu davet bulunamadı ya da daha önce kullanılmış." : e.message
            } catch {}
        }
    }

    private func accept() {
        busy = true
        Task {
            defer { busy = false }
            do {
                switch source {
                case .invite(let invite): try await companies.accept(inviteId: invite.id)
                case .token(let token): try await companies.accept(token: token)
                }
                dismiss()
            } catch let e as APIError {
                error = e.status == 409 ? "Zaten bu şirketin ekibindesin." : e.message
            } catch {}
        }
    }

    /// In-app invites are declined on the server; a link invite can only be
    /// ignored (it expires when used or cancelled).
    private func decline() {
        guard case .invite(let invite) = source else { return dismiss() }
        busy = true
        Task {
            defer { busy = false }
            try? await companies.decline(inviteId: invite.id)
            dismiss()
        }
    }
}

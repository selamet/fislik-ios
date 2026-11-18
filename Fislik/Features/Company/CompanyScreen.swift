import SwiftUI

/// "Şirket" tab for owners and admins (design `02-company-tab`): company card
/// with tax id and the shared credit pool, the team (roles, this month's
/// uploads, pending invites) and links to the accountant and tax profile.
struct CompanyScreen: View {
    @Environment(ClientRouter.self) private var router
    @State private var companies = CompanyStore.shared
    @State private var store = ReceiptStore.shared
    @State private var members: [CompanyMember] = []
    @State private var profile: CompanyProfile?
    @State private var loading = false
    @State private var error: String?
    @State private var managing: CompanyMember?
    @State private var resent: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    Text("Şirket").fFont(30, .heavy, tracking: -0.9)
                    Spacer()
                    if let role = companies.active?.role {
                        Text(role.label)
                            .fFont(12, .heavy)
                            .foregroundStyle(FColor.brand)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(.top, 44)

                if let company = companies.active {
                    companyCard(company)
                }

                if let error {
                    FBanner(icon: .circleAlert, tone: .danger, text: Text(error))
                }

                team
                links
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .refreshable { await load() }
        .background(FColor.bg.ignoresSafeArea())
        .fStatusBarBackdrop()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: companies.activeId) { await load() }
        .confirmationDialog(managing?.displayName ?? "", isPresented: Binding(get: { managing != nil }, set: { if !$0 { managing = nil } }), titleVisibility: .visible) {
            if let member = managing {
                if !member.isPending {
                    ForEach([MemberRole.admin, .uploader], id: \.self) { role in
                        if role != member.role {
                            Button("\(role.label) yap") { Task { await change(member, to: role) } }
                        }
                    }
                }
                Button(member.isPending ? "Daveti iptal et" : "Ekipten çıkar", role: .destructive) {
                    Task { await remove(member) }
                }
            }
        }
    }

    // MARK: Sections

    private func companyCard(_ company: CompanyMembership) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FAvatar(initials: company.initials, size: 48, radius: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name).fFont(17, .heavy, tracking: -0.3).lineLimit(1)
                    if let profile {
                        Text("\(profile.taxOffice) V.D. · \(profile.taxNumber)").fFont(12, .semibold).foregroundStyle(FColor.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            if let credits = store.credits {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Şirket analiz kredisi").foregroundStyle(FColor.muted)
                        Spacer()
                        if credits.unlimited {
                            Text("Sınırsız")
                        } else {
                            Text("\(credits.remaining ?? 0) ") + Text("/ \(credits.limit ?? 0)").foregroundColor(FColor.muted).fontWeight(.semibold)
                        }
                    }
                    .fFont(12, .bold)
                    if !credits.unlimited {
                        CreditBar(
                            fraction: Double(credits.remaining ?? 0) / Double(max(credits.limit ?? 1, 1)),
                            track: FColor.tint,
                            fill: credits.exhausted ? FColor.warning : FColor.brand,
                            height: 7
                        )
                    }
                    Text("Tüm üyeler bu havuzu kullanır · \(Period.current.renewalLabel)'da yenilenir")
                        .fFont(11, .semibold).foregroundStyle(FColor.muted)
                }
            }
        }
        .padding(16)
        .fCard(radius: 20)
    }

    @ViewBuilder
    private var team: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EKİP · \(members.filter { !$0.isPending }.count)").fEyebrow()
                Spacer()
                Button { router.sheet = .inviteMember } label: {
                    HStack(spacing: 5) {
                        Icon(.plus, size: 16)
                        Text("Üye davet et")
                    }
                    .fFont(13, .heavy)
                    .foregroundStyle(FColor.brand)
                    .frame(height: 44)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
            if loading && members.isEmpty {
                FSkeleton().frame(height: 130)
            } else if !members.isEmpty {
                FGroupedCard {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { RowDivider() }
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: CompanyMember) -> some View {
        let viewerRole = companies.active?.role ?? .uploader
        let manageable = member.manageable(by: viewerRole)
        return HStack(spacing: 12) {
            if member.isPending {
                Icon(.mail, size: 17)
                    .foregroundStyle(FColor.muted)
                    .frame(width: 38, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            } else {
                FAvatar(
                    initials: member.displayName.initials,
                    size: 38,
                    radius: 12,
                    foreground: member.isMe ? FColor.brand : FColor.ink2,
                    background: member.isMe ? FColor.brand.opacity(0.1) : FColor.tint
                )
            }
            VStack(alignment: .leading, spacing: 1) {
                if member.isPending {
                    Text(member.email).fFont(14, .bold).lineLimit(1)
                    Text("Davet bekliyor · \(member.role.label)").fFont(12, .semibold).foregroundStyle(FColor.warning)
                } else {
                    (Text(member.displayName) + (member.isMe ? Text(" (sen)").foregroundColor(FColor.muted).fontWeight(.semibold) : Text("")))
                        .fFont(14, .bold).lineLimit(1)
                    Text(member.role == .owner ? member.role.label : "\(member.role.label) · bu ay \(member.receiptsThisMonth) fiş")
                        .fFont(12, .semibold).foregroundStyle(FColor.muted)
                }
            }
            Spacer(minLength: 8)
            if member.isPending && manageable {
                FMiniButton(title: resent.contains(member.id) ? "Gönderildi" : "Tekrar gönder") {
                    Task { await resend(member) }
                }
                .disabled(resent.contains(member.id))
            } else if manageable {
                Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
            }
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if manageable { managing = member } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(manageable ? .isButton : [])
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ŞİRKET").fEyebrow()
            FGroupedCard {
                Button { router.companyPath.append(.accountants) } label: {
                    SettingsRow(icon: .users, title: "Muhasebeci") {
                        if let name = store.activeAccountant?.counterpartName {
                            Text(name).fFont(12.5, .semibold).foregroundStyle(FColor.muted)
                        }
                        Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { router.companyPath.append(.company) } label: {
                    SettingsRow(icon: .building, title: "Vergi bilgileri") {
                        Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func load() async {
        guard let id = companies.activeId else { return }
        loading = true
        defer { loading = false }
        async let membersCall = API.members(id)
        async let profileCall = API.company()
        do {
            members = try await membersCall
            error = nil
        } catch let e as APIError {
            if !e.isCancellation { error = e.message }
        } catch {}
        profile = (try? await profileCall) ?? nil
        await store.refreshCredits()
        await store.refreshGrants()
    }

    private func change(_ member: CompanyMember, to role: MemberRole) async {
        guard let id = companies.activeId else { return }
        await run { _ = try await API.changeMemberRole(id, memberId: member.id, role: role) }
    }

    private func remove(_ member: CompanyMember) async {
        guard let id = companies.activeId else { return }
        await run { try await API.removeMember(id, memberId: member.id) }
    }

    private func resend(_ member: CompanyMember) async {
        guard let id = companies.activeId else { return }
        do {
            try await API.resendMemberInvite(id, memberId: member.id)
            resent.insert(member.id)
        } catch let e as APIError {
            error = e.message
        } catch {}
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
            await load()
            await companies.load()
        } catch let e as APIError {
            error = e.status == 403 ? "Bu üyeyi yönetme yetkin yok." : e.message
        } catch {}
    }
}

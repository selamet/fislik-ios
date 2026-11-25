import Foundation

/// Turkish copy shared by the invite landing, the signed-in invite sheet and
/// the welcome screen (mirrors fislik-web's `lib/inviteCopy.ts`).
enum InviteCopy {
    static let memberRoleInSentence = ["owner": "sahip", "admin": "yönetici", "uploader": "fiş yükleyici"]

    static func accountRoleLabel(_ role: UserRole) -> String {
        role == .accountant ? "muhasebeci" : "mükellef"
    }

    static func badge(_ info: InviteLookup) -> String {
        info.kind == .member ? "EKİP DAVETİ" : "MUHASEBECİ DAVETİ"
    }

    static func headline(_ info: InviteLookup) -> String {
        if info.kind == .member {
            return "\(info.companyName ?? "Şirket") şirketine \(memberRoleInSentence[info.role] ?? info.role) olarak davet edildin"
        }
        if info.role == "accountant" {
            return "\(info.companyName ?? info.inviterName ?? "Bir şirket") seni muhasebecisi olarak eklemek istiyor"
        }
        return "\(info.inviterName ?? "Muhasebecin") seni mükellefi olarak eklemek istiyor"
    }

    static func benefits(kind: InviteKind, role: String) -> [String] {
        switch (kind, role) {
        case (.member, "uploader"):
            ["Fişlerin fotoğrafını çekip şirkete yüklersin", "Analiz kredisi şirketten düşer, senden değil", "İstediğin zaman ekipten ayrılabilirsin"]
        case (.member, _):
            ["Şirketin fişlerini görür ve yönetirsin", "Ekibe yeni üye davet edebilirsin", "İstediğin zaman ekipten ayrılabilirsin"]
        case (.grant, "accountant"):
            ["Mükellefinin yüklediği fişleri görürsün", "Analiz sonuçlarını düzenler, ayları kapatırsın", "Bağlantıyı istediğin zaman kaldırabilirsin"]
        default:
            ["Fişlerinin fotoğrafını çekip yüklersin", "Muhasebecin fişlerini anında görür", "Bağlantıyı istediğin zaman kaldırabilirsin"]
        }
    }

    struct Welcome: Equatable {
        let title: String
        let action: String
        /// True when the primary action opens the camera.
        let opensCamera: Bool
    }

    static func welcome(_ joined: JoinedViaInvite) -> Welcome {
        let company = joined.companyName ?? "Şirket"
        switch (joined.kind, joined.role) {
        case (.member, "uploader"):
            return Welcome(title: "\(company) ekibine katıldın", action: "İlk fişini çek", opensCamera: true)
        case (.member, _):
            return Welcome(title: "\(company) ekibine yönetici olarak katıldın", action: "Fişlere göz at", opensCamera: false)
        case (.grant, "accountant"):
            return Welcome(title: "\(company) artık mükelleflerinde", action: "Mükellefleri gör", opensCamera: false)
        default:
            let title = joined.inviterName.map { "Muhasebecin \($0) bağlandı" } ?? "Muhasebecin bağlandı"
            return Welcome(title: title, action: "İlk fişini çek", opensCamera: true)
        }
    }

    static let gone = "Bu davet artık geçerli değil."
}

extension JoinedViaInvite: Identifiable {
    var id: String { "\(kind.rawValue)-\(companyId ?? "")-\(role)" }
}

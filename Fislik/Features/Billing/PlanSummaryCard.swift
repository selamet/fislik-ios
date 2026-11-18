import SwiftUI

/// What a plan offers, as shown on the plan screen.
///
/// Plans differ only by their monthly receipt limit today, so paid plans say
/// "everything in the lower plan" and name the capabilities that matter at
/// volume — none of these lines claims a capability is exclusive to a plan.
enum PlanFeatures {
    static func tagline(_ code: String) -> String {
        switch code {
        case "pro": "Düzenli fiş toplayan işletmeler için"
        case "business": "Yoğun fiş trafiği olan ekipler için"
        default: "Fişlik'i denemek için"
        }
    }

    /// Team size line of a plan card.
    static func team(_ maxMembers: Int?) -> String {
        switch maxMembers {
        case nil: "Sınırsız ekip üyesi"
        case 1?: "Tek kullanıcı (yalnızca şirket sahibi)"
        case let count?: "\(count) kişilik ekip"
        }
    }

    /// Feature lines after the receipt limit and team size, which the card
    /// prints itself.
    static func features(_ code: String) -> [String] {
        switch code {
        case "pro":
            [
                "Ücretsiz plandaki her şey",
                "Yapay zekâ ile kategori ve KDV dağılımı analizi",
                "Ekip üyeleriyle ortak fiş havuzu",
                "Hatalı okumalarda yeniden analiz",
            ]
        case "business":
            [
                "Pro plandaki her şey",
                "Kalabalık ekipler için geniş ortak havuz",
                "Ay boyunca kesintisiz fiş okuma",
            ]
        default:
            [
                "Yapay zekâ ile fiş okuma: tutar, KDV, tarih, VKN",
                "Muhasebecinle tek dokunuşla paylaşım",
            ]
        }
    }

    /// What the team limit dialog says.
    static let teamLimitMessage = "Ücretsiz planda ekip yalnızca şirket sahibinden oluşur. Pro planda 3 kişiye kadar, İşletme planında sınırsız üye ekleyebilirsin. Bekleyen davetler de ekip sayısına dahildir."

    /// The plan to nudge towards when the company is on the free plan.
    static let recommended = "pro"
}

/// The company's plan at a glance, with an explicit way to the plan screen.
/// Shown on the company and profile screens; the whole card is tappable.
struct PlanSummaryCard: View {
    let billing: Billing?
    let credits: Credits?
    /// Whether the signed-in member may change the plan (owner / admin).
    let canManage: Bool
    let open: () -> Void

    private var usage: Credits? { billing?.usage ?? credits }
    private var isPaid: Bool { billing?.plan.isPaid ?? false }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    FIconTile(icon: .sparkles, size: 36, iconSize: 17)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PLANIN").fEyebrow()
                        Text(billing.map { "\($0.plan.name) plan" } ?? "Plan").fFont(16, .heavy, tracking: -0.3)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
                }

                if let usage {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            if usage.unlimited {
                                Text("Sınırsız fiş okuma").fFont(13, .bold)
                            } else {
                                (Text("\(usage.used)").font(FFont.jakarta(20, .heavy))
                                    + Text(" / \(usage.limit ?? 0) fiş").font(FFont.jakarta(13, .bold)).foregroundColor(FColor.muted))
                            }
                            Spacer()
                            Text("bu ay").fFont(12, .semibold).foregroundStyle(FColor.muted)
                        }
                        if !usage.unlimited {
                            CreditBar(
                                fraction: Double(usage.used) / Double(max(usage.limit ?? 1, 1)),
                                track: FColor.tint,
                                fill: usage.exhausted ? FColor.warning : FColor.brand,
                                height: 7
                            )
                        }
                        Text(Self.footnote(usage))
                            .fFont(11.5, .semibold)
                            .foregroundStyle(usage.exhausted ? FColor.warning : FColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if canManage {
                    Text(isPaid ? "Planı yönet" : "Planı yükselt")
                        .fFont(14, .heavy)
                        .foregroundStyle(isPaid ? FColor.brand : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            isPaid ? FColor.brand.opacity(0.1) : FColor.brand,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                } else {
                    Text("Planı şirket sahibi ya da yöneticisi değiştirebilir.")
                        .fFont(11.5, .semibold)
                        .foregroundStyle(FColor.muted)
                }
            }
            .foregroundStyle(FColor.ink)
            .padding(16)
            .fCard(radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-summary")
    }

    static func footnote(_ usage: Credits) -> String {
        let reset = "\(Period.current.renewalLabel)'da sıfırlanır"
        if usage.unlimited { return "Tüm üyeler aynı havuzu kullanır" }
        if usage.exhausted { return "Limit doldu; yeni fişler okunmayı bekler · \(reset)" }
        return "Tüm üyeler aynı havuzu kullanır · \(reset)"
    }
}

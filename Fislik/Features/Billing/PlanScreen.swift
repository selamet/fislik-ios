import StoreKit
import SwiftUI

/// Plan screen (paywall): the plan in effect, this month's usage and the
/// plans sold through the App Store.
struct PlanScreen: View {
    @State private var store = BillingStore.shared
    @State private var managing = false

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Plan")
            ScrollView {
                VStack(spacing: 12) {
                    if let billing = store.billing {
                        PlanHero(billing: billing)
                        if let managed = Self.managedElsewhere(billing) {
                            FBanner(icon: .store, tone: .brand, text: Text(managed))
                                .accessibilityIdentifier("managed-elsewhere")
                        }
                        if let notice = store.notice { noticeBanner(notice) }
                        ForEach(store.plans) { plan in
                            PlanCard(
                                plan: plan,
                                price: store.price(for: plan),
                                action: store.action(for: plan),
                                working: store.purchasing == plan.code,
                                disabled: store.busy
                            ) {
                                Task { await store.purchase(plan) }
                            }
                        }
                        footer(billing)
                    } else if let error = store.error {
                        FBanner(icon: .circleAlert, tone: .danger, text: Text(error.message))
                        Button("Tekrar dene") { Task { await store.load() } }.buttonStyle(.fSecondary)
                    } else {
                        ProgressView().padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $managing)
        .task { await store.load() }
    }

    /// Explains a subscription that is not an App Store one: it is shown
    /// here, but bought, changed and cancelled where it came from.
    static func managedElsewhere(_ billing: Billing) -> String? {
        switch billing.subscription?.source {
        case .iyzico:
            return "Şirketin aboneliği web üzerinden alındı. Plan değişikliği ve iptal için fislik.selamet.dev adresinde Şirket > Plan sayfasını kullan; buradan ayrıca satın alma yapılamaz."
        case .manual:
            return "Şirketin planı Fişlik tarafından tanımlandı. Değişiklik için destek ekibine yaz."
        case .appStore, .none:
            return nil
        }
    }

    private func noticeBanner(_ notice: BillingNotice) -> some View {
        let (icon, tone): (FIcon, FBannerTone) = switch notice.tone {
        case .success: (.circleCheck, .success)
        case .info: (.clock, .neutral)
        case .error: (.circleAlert, .danger)
        }
        return FBanner(icon: icon, tone: tone, text: Text(notice.text))
            .accessibilityIdentifier("billing-notice")
    }

    @ViewBuilder
    private func footer(_ billing: Billing) -> some View {
        VStack(spacing: 10) {
            if billing.canManage {
                Button {
                    Task { await store.restore() }
                } label: {
                    Text(store.restoring ? "Geri yükleniyor…" : "Satın alımları geri yükle")
                }
                .buttonStyle(.fSecondary)
                .disabled(store.busy)
                if billing.subscription?.source == .appStore {
                    Button("Aboneliği yönet") { managing = true }
                        .fFont(13.5, .heavy)
                        .foregroundStyle(FColor.brand)
                }
            }
            Text("Abonelikler aylıktır ve dönem bitiminden en az 24 saat önce iptal edilmedikçe kendiliğinden yenilenir. Ödeme Apple hesabından alınır; aboneliği App Store hesap ayarlarından yönetebilir ve iptal edebilirsin. Limit şirket başına sayılır.")
                .fFont(11.5, .semibold)
                .foregroundStyle(FColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Kullanım Koşulları", destination: APIConfig.webURL.appendingPathComponent("kosullar"))
                Link("Gizlilik Politikası", destination: APIConfig.webURL.appendingPathComponent("gizlilik"))
            }
            .fFont(12, .heavy)
            .foregroundStyle(FColor.brand)
        }
        .padding(.top, 6)
    }
}

/// Current plan and usage.
struct PlanHero: View {
    let billing: Billing

    var body: some View {
        let usage = billing.usage
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEVCUT PLAN · \(billing.plan.name.uppercased(with: Locale(identifier: "tr_TR")))")
                        .fFont(11, .heavy, tracking: 0.4)
                        .foregroundStyle(.white.opacity(0.75))
                    if usage.unlimited {
                        Text("Sınırsız").fFont(34, .heavy, tracking: -1)
                    } else {
                        (Text("\(usage.used) ").font(FFont.jakarta(34, .heavy)).tracking(-1)
                            + Text("/ \(usage.limit ?? 0) fiş").font(FFont.jakarta(16, .bold)).foregroundColor(.white.opacity(0.75)))
                    }
                }
                Spacer()
                Icon(.sparkles, size: 22)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !usage.unlimited {
                CreditBar(fraction: Double(usage.used) / Double(max(usage.limit ?? 1, 1)), track: .white.opacity(0.2), fill: .white, height: 8)
            }
            Text(Self.statusLine(billing))
                .fFont(12, .semibold)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FColor.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan-hero")
    }

    /// When the plan renews or ends, or when the monthly count starts over.
    static func statusLine(_ billing: Billing) -> String {
        let reset = "Kullanım \(Period.current.renewalLabel)'da sıfırlanır"
        guard let subscription = billing.subscription else { return reset }
        if subscription.isPastDue {
            return "Son ödeme alınamadı; şirket ücretsiz plan limitiyle çalışıyor."
        }
        guard subscription.isActive, let end = subscription.currentPeriodEnd else { return reset }
        let day = TR.longDay(end)
        return subscription.cancelAtPeriodEnd || subscription.source == .manual
            ? "Plan \(day) tarihine kadar geçerli · \(reset)"
            : "\(day) tarihinde yenilenir · \(reset)"
    }
}

struct PlanCard: View {
    let plan: Plan
    let price: String
    let action: PlanAction
    let working: Bool
    let disabled: Bool
    let buy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).fFont(19, .heavy, tracking: -0.4)
                    Text(PlanFeatures.tagline(plan.code)).fFont(12, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer()
                if action == .current {
                    badge("Mevcut plan", FColor.brand, FColor.brand.opacity(0.1))
                } else if recommended {
                    badge("Önerilen", .white, FColor.brand)
                }
            }
            if plan.isPaid {
                // The free plan's name already says what it costs.
                (Text(price).font(FFont.jakarta(24, .heavy)).tracking(-0.6)
                    + Text(" / ay").font(FFont.jakarta(13, .bold)).foregroundColor(FColor.muted))
            }
            VStack(alignment: .leading, spacing: 8) {
                feature("Ayda \(plan.monthlyReceipts) fiş okuma", strong: true)
                ForEach(PlanFeatures.features(plan.code), id: \.self) { feature($0) }
            }
            .padding(.vertical, 2)
            switch action {
            case .buy:
                Button(action: buy) {
                    Text(working ? "Satın alınıyor…" : "\(plan.name) planına geç")
                }
                .buttonStyle(.fPrimary)
                .disabled(disabled)
                .accessibilityIdentifier("buy-\(plan.code)")
            case .unavailable:
                note("Bu plan şu an App Store'da satın alınamıyor.")
            case .managedOnWeb, .managedBySupport, .current, .none:
                // Managed elsewhere: explained once by the banner above the cards.
                EmptyView()
            }
        }
        .foregroundStyle(FColor.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fCard(radius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(action == .current || recommended ? FColor.brand.opacity(0.45) : .clear, lineWidth: 1.5)
        )
        .accessibilityIdentifier("plan-\(plan.code)")
    }

    /// Pro is pointed out while the company is still deciding.
    private var recommended: Bool { plan.code == PlanFeatures.recommended && action == .buy }

    private func badge(_ text: String, _ foreground: Color, _ background: Color) -> some View {
        Text(text)
            .fFont(11, .heavy)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func feature(_ text: String, strong: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.check, size: 15).foregroundStyle(FColor.brand).padding(.top, 1)
            Text(text).fFont(13.5, strong ? .heavy : .semibold).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).fFont(12, .semibold).foregroundStyle(FColor.muted).fixedSize(horizontal: false, vertical: true)
    }
}

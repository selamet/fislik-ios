import SwiftUI

/// 2A — first-launch pager. Walks through the same five stages as the web
/// landing page (capture → upload → analysis → send → accountant export),
/// each illustrated with a Blender render from `docs/design/onboarding`.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0

    private let pages = OnboardingPage.all

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    FislikMark(height: 28)
                    Text("Fişlik").fFont(19, .bold, tracking: -1)
                }
                Spacer()
                Button("Atla") { app.finishOnboarding() }
                    .fFont(14, .bold)
                    .foregroundStyle(FColor.brand)
            }
            .frame(height: 44)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    OnboardingArt(page: pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.vertical, 12)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? FColor.brand : FColor.ink.opacity(0.15))
                        .frame(width: i == page ? 22 : 6, height: 6)
                }
                Spacer()
                if let step = pages[page].step {
                    StepTag(step: step, total: OnboardingPage.stepCount, who: pages[page].who)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            .padding(.bottom, 14)

            Group {
                Text(pages[page].title)
                    .fFont(30, .heavy, tracking: -0.8)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pages[page].body)
                    .fFont(14.5, .medium)
                    .foregroundStyle(FColor.muted)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(page)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.2), value: page)
            .frame(minHeight: 132, alignment: .top)

            Button(isLast ? "Başla" : "Devam") {
                if isLast {
                    app.finishOnboarding()
                } else {
                    withAnimation(.spring(duration: 0.35)) { page += 1 }
                }
            }
            .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
            .padding(.top, 20)

            HStack(spacing: 4) {
                Text("Zaten hesabın var mı?").foregroundStyle(FColor.muted)
                Button("Giriş yap") { app.finishOnboarding() }.foregroundStyle(FColor.brand).fontWeight(.bold)
            }
            .fFont(13, .semibold)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .background(FAuthBackground())
    }
}

/// One onboarding page: a Blender render plus copy. `step` is nil for the
/// opening welcome page.
struct OnboardingPage {
    let image: String
    let step: Int?
    let who: String?
    let title: String
    let body: String

    static let stepCount = 5

    static let all: [OnboardingPage] = [
        OnboardingPage(
            image: "OnboardingHero", step: nil, who: nil,
            title: "Fişini çek,\ngerisini Fişlik halletsin.",
            body: "Fişlerin cüzdanda kaybolmasın. Beş adımda fotoğraftan muhasebecinin tablosuna."
        ),
        OnboardingPage(
            image: "OnboardingStep1", step: 1, who: "Sen",
            title: "Fişin fotoğrafını çek",
            body: "Market fişi, fatura ya da gider pusulası fark etmez. Kamerayı aç, fişi kadraja al, çek."
        ),
        OnboardingPage(
            image: "OnboardingStep2", step: 2, who: "Sen",
            title: "Yükle",
            body: "Fotoğraf saniyeler içinde güvenle yüklenir. İnternet yoksa sıraya alınır, bağlantı gelince gönderilir."
        ),
        OnboardingPage(
            image: "OnboardingStep3", step: 3, who: "Fişlik",
            title: "Analiz edilsin",
            body: "Tarih, firma, tutar ve KDV oranı otomatik okunur. Yanlış bir şey varsa tek dokunuşla düzeltirsin."
        ),
        OnboardingPage(
            image: "OnboardingStep4", step: 4, who: "Sen",
            title: "Muhasebecine gönder",
            body: "Ay bitince o ayın fişlerini tek dokunuşla teslim et. Sorunlu fiş olursa bildirim gelir."
        ),
        OnboardingPage(
            image: "OnboardingStep5", step: 5, who: "Muhasebecin",
            title: "Muhasebecin dilediği gibi export etsin",
            body: "Muhasebecin ayı Excel tablosu ya da fotoğraflarıyla birlikte ZIP olarak indirir."
        ),
    ]
}

private struct StepTag: View {
    let step: Int
    let total: Int
    let who: String?

    var body: some View {
        HStack(spacing: 6) {
            Text("ADIM \(step)/\(total)").fFont(10.5, .heavy, tracking: 0.4)
            if let who {
                Circle().fill(FColor.brand.opacity(0.4)).frame(width: 3, height: 3)
                Text(who).fFont(11, .bold)
            }
        }
        .foregroundStyle(FColor.brand)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(FColor.brand.opacity(0.1), in: Capsule())
        .transition(.opacity)
    }
}

private struct OnboardingArt: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(RadialGradient(colors: [FColor.brand.opacity(0.14), FColor.brand.opacity(0)], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 230))
            Image(page.image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
                .padding(.horizontal, page.step == nil ? 0 : 4)
        }
    }
}

/// "● %20 ₺821,27" chip used in totals.
struct VatChip: View {
    let rate: Int
    let amount: Decimal

    var color: Color { rate >= 18 ? FColor.brand : rate >= 8 ? FColor.warning : FColor.info }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("%\(rate)").fFont(10.5, .semibold)
            Text(TR.money(amount)).fFont(10.5, .heavy)
        }
        .foregroundStyle(FColor.ink2)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

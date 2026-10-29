import SwiftUI

/// 2A — first-launch pager.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        ("Fişini çek,\ngerisini Fişlik halletsin.", "Fotoğraf çekildiği an yüklenir, tutar ve KDV okunur, aya göre dosyalanır. Muhasebecin aynı anda görür."),
        ("Muhasebecin\nanında görür.", "Ay sonunda tek dokunuşla gönder. Muhasebecin soru sorarsa bildirim gelir, fişin üstünde cevaplarsın."),
        ("KDV kırılımı\nhazır, ay kapanır.", "%1, %10, %20 KDV ayrı ayrı toplanır. Muhasebecin ayı işler ve kapatır; sen sadece fiş çekersin."),
    ]

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
                    OnboardingArt(page: i).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.vertical, 20)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? FColor.brand : FColor.ink.opacity(0.15))
                        .frame(width: i == page ? 22 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            .padding(.bottom, 16)

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

            Button("Başla") { app.finishOnboarding() }
            .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
            .padding(.top, 24)

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

private struct OnboardingArt: View {
    let page: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(RadialGradient(colors: [FColor.brand.opacity(0.14), FColor.brand.opacity(0)], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 220))
            switch page {
            case 0: receiptArt
            case 1: accountantArt
            default: vatArt
            }
        }
    }

    private var receiptArt: some View {
        ZStack {
            BigReceipt()
            floatingChip { FStatusDot(text: "İşlendi", color: FColor.success).fFont(10, .heavy) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 10).padding(.top, 40)
            floatingChip {
                HStack(spacing: 8) {
                    Icon(.sparkles, size: 16).foregroundStyle(FColor.brand)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tutar ve KDV").fFont(11, .bold)
                        Text("otomatik okundu").fFont(11, .semibold).foregroundStyle(FColor.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 14).padding(.bottom, 36)
        }
    }

    private var accountantArt: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                FAvatar(initials: "ZK", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zeynep Kaya").fFont(15, .heavy)
                    Text("Kaya Müşavirlik").fFont(12, .medium).foregroundStyle(FColor.muted)
                }
                Spacer()
                FStatusBadge(text: "Aktif", color: FColor.success)
            }
            .padding(14).fCard(radius: 16)
            HStack(spacing: 10) {
                Icon(.send, size: 16).foregroundStyle(FColor.brand)
                Text("Ekim fişleri gönderildi · 8 fiş").fFont(13, .semibold)
                Spacer()
            }
            .padding(14).fCard(radius: 16)
            HStack(alignment: .top, spacing: 10) {
                Icon(.triangleAlert, size: 16).foregroundStyle(FColor.warning)
                Text("Bu fatura şirket adına mı kesilmiş?").fFont(13, .semibold)
                Spacer()
            }
            .padding(14)
            .background(FColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
    }

    private var vatArt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOPLAM").fFont(10, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
            Text("₺6.345,25").fFont(28, .heavy, tracking: -0.5)
            HStack(spacing: 6) {
                VatChip(rate: 20, amount: Decimal(string: "821.27")!)
                VatChip(rate: 10, amount: Decimal(string: "150.58")!)
            }
            Divider().padding(.vertical, 4)
            HStack {
                Icon(.lock, size: 15).foregroundStyle(FColor.brand)
                Text("Eylül 2026 kapatıldı").fFont(13, .bold)
            }
        }
        .padding(18)
        .fCard(radius: 18)
        .shadow(color: FColor.ink.opacity(0.15), radius: 20, y: 14)
        .padding(.horizontal, 36)
    }

    private func floatingChip(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FColor.ink.opacity(0.06)))
            .shadow(color: FColor.ink.opacity(0.2), radius: 14, y: 10)
    }
}

/// The large Migros receipt illustration from 2A.
private struct BigReceipt: View {
    var body: some View {
        VStack(spacing: 7) {
            Text("MİGROS").fFont(12, .heavy, tracking: 0.5)
            Text("KADIKÖY · 24.10.2026 14:03").fFont(7, .medium).foregroundStyle(Color(hex: 0x6C7A78))
            dashed
            line("SÜT 1L", "58,90")
            line("EKMEK", "15,00")
            line("ZEYTİNYAĞI 2L", "789,00")
            line("…", "")
            dashed
            HStack { Text("TOPLAM"); Spacer(); Text("1.482,35") }.fFont(11, .heavy)
            HStack { Text("KDV %20 / %10"); Spacer(); Text("246,52") }.fFont(7.5, .medium).foregroundStyle(Color(hex: 0x6C7A78))
        }
        .foregroundStyle(Color(hex: 0x0C1A18))
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 22)
        .frame(width: 200)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color(hex: 0x0C1A18).opacity(0.3), radius: 24, y: 20)
        .rotationEffect(.degrees(-4))
    }

    private var dashed: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).foregroundStyle(Color(hex: 0xD8E0DE)).frame(height: 1).padding(.vertical, 4)
    }

    private func line(_ a: String, _ b: String) -> some View {
        HStack { Text(a); Spacer(); Text(b) }.fFont(8, .medium).foregroundStyle(Color(hex: 0x3F4E4C))
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
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

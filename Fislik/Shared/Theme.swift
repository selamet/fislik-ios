import SwiftUI

/// Brand tokens ported from the Fişlik web app / "Fislik iOS v2" design.
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Dark-mode aware color pair.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let (hex, alpha) = traits.userInterfaceStyle == .dark ? (dark, darkOpacity) : (light, lightOpacity)
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

enum FColor {
    static let brand = Color(hex: 0x0F766E)
    static let brandDark = Color(hex: 0x0B5C55)
    static let ink = Color(light: 0x0C1A18, dark: 0xEEF3F2)
    static let ink2 = Color(light: 0x3F4E4C, dark: 0xC9D3D1)
    static let muted = Color(light: 0x52605E, dark: 0x9AA8A6)
    static let faint = Color(light: 0x6C7A78, dark: 0x7D8B89)
    static let bg = Color(light: 0xF5F8F7, dark: 0x0B1211)
    static let bgTop = Color(light: 0xF5F8F7, dark: 0x0B1211)
    static let bgBottom = Color(light: 0xE9EEED, dark: 0x0F1716)
    static let card = Color(light: 0xFFFFFF, dark: 0x16201F)
    static let field = Color(light: 0xF9FAFB, dark: 0x1C2726)
    static let fieldBorder = Color(light: 0xE5E7EB, dark: 0x2A3937)
    static let line = Color(light: 0x0C1A18, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.08)
    static let lineStrong = Color(light: 0x0C1A18, dark: 0xFFFFFF, lightOpacity: 0.12, darkOpacity: 0.14)
    static let thumb = Color(light: 0xE3EAE8, dark: 0x22302E)
    static let tint = Color(light: 0xEEF3F2, dark: 0x1A2524)
    static let success = Color(hex: 0x12A18A)
    static let warning = Color(hex: 0xE08A2B)
    static let danger = Color(hex: 0xC0392B)
    static let info = Color(hex: 0x1D4ED8)
    static let scrim = Color(hex: 0x3A4846)
    static let cameraBg = Color(hex: 0x0B1211)
}

enum FFont {
    static let family = "Plus Jakarta Sans"

    /// Design sizes are in CSS px which map 1:1 to iOS points at 402pt width.
    static func jakarta(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(family, size: size).weight(weight)
    }
}

extension View {
    func fFont(_ size: CGFloat, _ weight: Font.Weight = .medium, tracking: CGFloat = 0) -> some View {
        font(FFont.jakarta(size, weight)).tracking(tracking)
    }

    /// Uppercase section label, e.g. "FİŞLER", "BU HAFTA".
    func fEyebrow(_ color: Color = FColor.muted) -> some View {
        fFont(11, .heavy, tracking: 0.4).foregroundStyle(color)
    }

    /// White card with hairline border (web: 1px rgba(12,26,24,.08), radius 16).
    func fCard(radius: CGFloat = 16, padding: CGFloat = 0) -> some View {
        self.padding(padding)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(FColor.line))
    }

    /// Brand button glow: 0 10px 20px -14px rgba(15,118,110,.95)
    func fBrandShadow() -> some View {
        shadow(color: FColor.brand.opacity(0.55), radius: 10, y: 8)
    }
}

extension Font.Weight {
    static let extraBold = Font.Weight.heavy
}

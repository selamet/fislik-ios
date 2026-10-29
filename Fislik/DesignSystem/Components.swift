import SwiftUI

// MARK: - Buttons

enum FButtonKind {
    case primary, secondary, dark, danger, dangerOutline
}

struct FButtonStyle: ButtonStyle {
    var kind: FButtonKind = .primary
    var height: CGFloat = 50
    var fontSize: CGFloat = 15
    var radius: CGFloat = 14
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fFont(fontSize, .bold)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border)
                }
            }
            .shadow(color: kind == .primary && isEnabled ? FColor.brand.opacity(0.55) : .clear, radius: 10, y: 8)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .dark, .danger: .white
        case .secondary: FColor.ink
        case .dangerOutline: FColor.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: FColor.brand
        case .secondary, .dangerOutline: FColor.card
        case .dark: Color(light: 0x0C1A18, dark: 0x000000)
        case .danger: FColor.danger
        }
    }

    private var border: Color? {
        switch kind {
        case .secondary, .dangerOutline: FColor.lineStrong
        default: nil
        }
    }
}

extension ButtonStyle where Self == FButtonStyle {
    static var fPrimary: FButtonStyle { FButtonStyle(kind: .primary) }
    static var fSecondary: FButtonStyle { FButtonStyle(kind: .secondary) }
    static var fDark: FButtonStyle { FButtonStyle(kind: .dark) }
    static var fDanger: FButtonStyle { FButtonStyle(kind: .danger) }
    static func f(_ kind: FButtonKind, height: CGFloat = 50, fontSize: CGFloat = 15, radius: CGFloat = 14) -> FButtonStyle {
        FButtonStyle(kind: kind, height: height, fontSize: fontSize, radius: radius)
    }
}

/// Primary button label with optional leading icon and spinner.
struct FButtonLabel: View {
    let title: String
    var icon: FIcon?
    var loading = false

    var body: some View {
        HStack(spacing: 9) {
            if loading {
                ProgressView().tint(.white)
            } else if let icon {
                Icon(icon, size: 18)
            }
            Text(title)
        }
    }
}

/// Small rounded square icon button used in headers (search, bell, chevrons).
struct FIconButton: View {
    let icon: FIcon
    var size: CGFloat = 38
    var iconSize: CGFloat = 18
    var badge: String?
    var tint: Color = FColor.muted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FColor.ink.opacity(0.1)))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        FCountBadge(text: badge).offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Red count badge (bell, tab bar).
struct FCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .fFont(9.5, .heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(FColor.danger, in: Capsule())
            .overlay(Capsule().strokeBorder(FColor.bg, lineWidth: 2))
    }
}

/// Text link with leading chevron, e.g. "‹ Geri".
struct FBackButton: View {
    var title = "Geri"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Icon(.chevronLeft, size: 20)
                Text(title).fFont(15, .bold)
            }
            .foregroundStyle(FColor.brand)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fields

struct FFieldLabel: View {
    let text: String
    var required = false

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
            if required { Text("*").foregroundStyle(FColor.danger) }
        }
        .fFont(12.5, .bold)
        .foregroundStyle(FColor.muted)
    }
}

/// Labelled text field: 48pt, radius 12, #f9fafb fill; focused = white + teal border; error = red border + message.
struct FTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var required = false
    var secure = false
    var error: String?
    var disabled = false
    var trailingIcon: FIcon?
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next
    var height: CGFloat = 48
    var onSubmit: () -> Void = {}

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { FFieldLabel(text: label, required: required) }
            HStack(spacing: 8) {
                Group {
                    if secure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .focused($focused)
                .fFont(15, .medium)
                .foregroundStyle(disabled ? FColor.muted : FColor.ink)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(secure || keyboard == .emailAddress)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .disabled(disabled)

                if secure {
                    Button { revealed.toggle() } label: { Icon(.eye, size: 17) }
                        .buttonStyle(.plain)
                        .foregroundStyle(FColor.muted)
                        .accessibilityLabel(revealed ? "Şifreyi gizle" : "Şifreyi göster")
                } else if let trailingIcon {
                    Icon(trailingIcon, size: 16).foregroundStyle(FColor.muted)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: height)
            .background(focused ? FColor.card : FColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: focused || error != nil ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if let error {
                Text(error).fFont(12, .semibold).foregroundStyle(FColor.danger)
            }
        }
    }

    private var borderColor: Color {
        if error != nil { return FColor.danger }
        return focused ? FColor.brand : FColor.fieldBorder
    }
}

/// Divider with centered caption: "──── veya e-posta ile ────"
struct FOrDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(FColor.lineStrong).frame(height: 1)
            Text(text).fFont(12, .semibold).foregroundStyle(FColor.muted).fixedSize()
            Rectangle().fill(FColor.lineStrong).frame(height: 1)
        }
    }
}

// MARK: - Chips & badges

/// Filter chip: selected = teal fill, white text; otherwise white with hairline border.
struct FChip: View {
    let title: String
    var selected = false
    var outlinedSelection = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fFont(12, .bold)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(border))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        guard selected else { return FColor.muted }
        return outlinedSelection ? FColor.brand : .white
    }

    private var background: Color {
        guard selected else { return FColor.card }
        return outlinedSelection ? FColor.brand.opacity(0.08) : FColor.brand
    }

    private var border: Color {
        guard selected else { return FColor.lineStrong }
        return outlinedSelection ? FColor.brand : FColor.brand
    }
}

/// Status pill with a colored dot: "● İşlendi", "● Sorun var".
struct FStatusBadge: View {
    let text: String
    let color: Color
    var filled = true

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).fFont(11, .bold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(filled ? FColor.card : color.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

/// Inline status: "● İşlendi" without background, used in list rows.
struct FStatusDot: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).fFont(12.5, .semibold)
        }
        .foregroundStyle(color)
    }
}

/// Small rounded tag, e.g. "Fatura", "Fatura · PDF" (blue).
struct FTag: View {
    let text: String
    var color: Color = FColor.info

    var body: some View {
        Text(text)
            .fFont(10.5, .bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Initials avatar: "AY", "ZK".
struct FAvatar: View {
    let initials: String
    var size: CGFloat = 42
    var radius: CGFloat = 12

    var body: some View {
        Text(initials)
            .fFont(size * 0.36, .heavy)
            .foregroundStyle(FColor.brand)
            .frame(width: size, height: size)
            .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Rounded square icon tile, e.g. key icon on password reset.
struct FIconTile: View {
    let icon: FIcon
    var size: CGFloat = 46
    var iconSize: CGFloat = 22
    var tint: Color = FColor.brand
    var background: Color?

    var body: some View {
        Icon(icon, size: iconSize)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background ?? tint.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Stat tiles

/// "FİŞ 8", "ANALİZ 8/8" tiles.
struct FStatTile: View {
    let title: String
    let value: String
    var suffix: String?
    var valueColor: Color = FColor.ink
    var suffixColor: Color = Color(hex: 0x9AA6A4)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fFont(10, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value).foregroundStyle(valueColor)
                if let suffix { Text(suffix).foregroundStyle(suffixColor) }
            }
            .fFont(18, .heavy, tracking: -0.3)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .fCard(radius: 14)
    }
}

// MARK: - Toggle

struct FToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? FColor.brand : FColor.lineStrong)
                .frame(width: 46, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2.5).shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .animation(.spring(duration: 0.2), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

// MARK: - Segmented control

/// Pill segmented control (Türkçe/English, Açık/Koyu/Sistem, Fiş/Fatura).
struct FSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var height: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title)
                        .fFont(13, .bold)
                        .foregroundStyle(selection == value ? .white : FColor.ink2)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 6)
                        .background(selection == value ? FColor.brand : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(FColor.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(FColor.lineStrong))
    }
}

// MARK: - Banners

enum FBannerTone {
    case warning, success, neutral, danger, brand

    var color: Color {
        switch self {
        case .warning: FColor.warning
        case .success: FColor.success
        case .neutral: FColor.muted
        case .danger: FColor.danger
        case .brand: FColor.brand
        }
    }
}

/// Tinted callout card with leading icon ("Bu ay muhasebecin tarafından kapatıldı…").
struct FBanner<Trailing: View>: View {
    let icon: FIcon
    let tone: FBannerTone
    let text: Text
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 17).foregroundStyle(tone.color).padding(.top, 1)
            text.fFont(13, .semibold).foregroundStyle(FColor.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(13)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tone.color.opacity(0.3)))
    }
}

extension FBanner where Trailing == EmptyView {
    init(icon: FIcon, tone: FBannerTone, text: Text) {
        self.init(icon: icon, tone: tone, text: text) { EmptyView() }
    }
}

// MARK: - Backgrounds

/// Auth screens use a soft vertical gradient (#f5f8f7 → #e9eeed).
struct FAuthBackground: View {
    var body: some View {
        LinearGradient(colors: [FColor.bgTop, FColor.bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Receipt thumbnail placeholder

/// Paper-like receipt illustration used while the image loads or for placeholders.
struct ReceiptPaper: View {
    var merchant: String = ""
    var total: String = ""
    var rotation: Double = -2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(merchant.uppercased(with: Locale(identifier: "tr_TR")))
                .fFont(6.5, .heavy)
                .frame(maxWidth: .infinity)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(FColor.ink.opacity(0.12)).frame(width: [70, 50, 62][i], height: 2.5)
            }
            Rectangle().fill(FColor.ink.opacity(0.15)).frame(height: 0.5).padding(.vertical, 2)
            HStack {
                Text("TOPLAM")
                Spacer()
                Text(total)
            }
            .fFont(5.5, .heavy)
        }
        .foregroundStyle(Color(hex: 0x0C1A18))
        .padding(8)
        .frame(width: 120)
        .background(Color(hex: 0xFFFFFF), in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Shimmer

struct FSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 10
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(FColor.ink.opacity(0.07))
            .frame(width: width, height: height)
            .opacity(pulse ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

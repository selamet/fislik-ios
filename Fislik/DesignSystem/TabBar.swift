import SwiftUI

struct FTabItem<Tab: Hashable>: Identifiable {
    let tab: Tab
    let title: String
    let icon: FIcon
    var badge: Int = 0

    var id: Tab { tab }
}

/// Custom bottom bar matching the design: white 96% background, hairline top border,
/// 22pt icon above a 10.5pt bold label, teal when selected.
struct FTabBar<Tab: Hashable>: View {
    let items: [FTabItem<Tab>]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 3) {
                        Icon(item.icon, size: 22)
                            .overlay(alignment: .topTrailing) {
                                if item.badge > 0 {
                                    Text(item.badge > 9 ? "9+" : "\(item.badge)")
                                        .fFont(9, .heavy)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(FColor.danger, in: Capsule())
                                        .offset(x: 7, y: -5)
                                }
                            }
                        Text(item.title).fFont(10.5, .bold)
                    }
                    .foregroundStyle(selection == item.tab ? FColor.brand : FColor.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) okunmamış" : item.title)
                .accessibilityAddTraits(selection == item.tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .background {
            Color(light: 0xFFFFFF, dark: 0x101918, lightOpacity: 0.96, darkOpacity: 0.96)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(FColor.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Floating camera button (58×58, radius 19) above the tab bar.
struct CameraFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(.camera, size: 24)
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(FColor.brand, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: FColor.brand.opacity(0.5), radius: 16, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fiş ekle")
    }
}

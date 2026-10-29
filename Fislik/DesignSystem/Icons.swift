import SwiftUI

/// Lucide icons (stroke 2) shipped as template vector assets under `Icons/`.
enum FIcon: String, CaseIterable {
    case receipt, users, bell, user, camera, images, chevronLeft, chevronRight, chevronDown
    case search, layoutGrid, list, x, pencil, trash, sparkles, triangleAlert, send, shieldCheck
    case building, keyRound, logOut, store, check, lock, clock, userPlus, userCheck, circleCheck
    case circleAlert, inbox, rotateCw, fileText, plus, download, arrowLeft, mail, apple, scanFace
    case zap, eye, ellipsis, share, calendar, zoomIn, sun, zapOff, flashlight, package
}

struct Icon: View {
    let icon: FIcon
    var size: CGFloat = 18

    init(_ icon: FIcon, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image("Icons/\(icon.rawValue)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The Fişlik mark: a teal receipt with a white "F" (assets/favicon.svg, viewBox 24×34).
struct FislikMark: View {
    var height: CGFloat = 24
    var fill: Color = FColor.brand
    var glyph: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 34
            var body = Path()
            let teeth: [(CGFloat, CGFloat)] = [(0, 2.2), (4, 0), (8, 2.2), (12, 0), (16, 2.2), (20, 0), (24, 2.2)]
            body.move(to: CGPoint(x: 0, y: 2.2 * s))
            for (x, y) in teeth.dropFirst() { body.addLine(to: CGPoint(x: x * s, y: y * s)) }
            body.addLine(to: CGPoint(x: 24 * s, y: 31.8 * s))
            let bottom: [(CGFloat, CGFloat)] = [(20, 34), (16, 31.8), (12, 34), (8, 31.8), (4, 34), (0, 31.8)]
            for (x, y) in bottom { body.addLine(to: CGPoint(x: x * s, y: y * s)) }
            body.closeSubpath()
            ctx.fill(body, with: .color(fill))

            var f = Path()
            let fPts: [(CGFloat, CGFloat)] = [(7, 8), (17, 8), (17, 11.2), (10.6, 11.2), (10.6, 14.6), (15.6, 14.6), (15.6, 17.8), (10.6, 17.8), (10.6, 22), (7, 22)]
            f.move(to: CGPoint(x: fPts[0].0 * s, y: fPts[0].1 * s))
            for (x, y) in fPts.dropFirst() { f.addLine(to: CGPoint(x: x * s, y: y * s)) }
            f.closeSubpath()
            ctx.fill(f, with: .color(glyph))
            ctx.fill(Path(roundedRect: CGRect(x: 7 * s, y: 24.4 * s, width: 10 * s, height: 1.7 * s), cornerRadius: 0.85 * s), with: .color(glyph.opacity(0.5)))
            ctx.fill(Path(roundedRect: CGRect(x: 7 * s, y: 27.4 * s, width: 6.4 * s, height: 1.7 * s), cornerRadius: 0.85 * s), with: .color(glyph.opacity(0.5)))
        }
        .frame(width: height * 24 / 34, height: height)
        .accessibilityHidden(true)
    }
}

/// Logo lockup used in the top-left of every main screen: mark + "Fişlik".
struct FislikLogo: View {
    var subtitle: String?

    var body: some View {
        HStack(spacing: 7) {
            FislikMark(height: 26)
            VStack(alignment: .leading, spacing: -2) {
                Text("Fişlik").fFont(18, .bold, tracking: -0.8).foregroundStyle(FColor.ink)
                if let subtitle {
                    Text(subtitle).fFont(9, .heavy, tracking: 0.4).foregroundStyle(FColor.brand)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fişlik")
    }
}

/// Google mark as drawn in the design: a four-color conic disc.
struct GoogleMark: View {
    var size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(AngularGradient(
                stops: [
                    .init(color: Color(hex: 0xEA4335), location: 0), .init(color: Color(hex: 0xEA4335), location: 0.25),
                    .init(color: Color(hex: 0xFBBC05), location: 0.25), .init(color: Color(hex: 0xFBBC05), location: 0.5),
                    .init(color: Color(hex: 0x34A853), location: 0.5), .init(color: Color(hex: 0x34A853), location: 0.75),
                    .init(color: Color(hex: 0x4285F4), location: 0.75), .init(color: Color(hex: 0x4285F4), location: 1),
                ],
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

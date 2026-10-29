import AVFoundation
import SwiftUI

/// 2L — full-screen scanner with auto detection and multi-shot.
struct CameraScreen: View {
    var period: Period?
    var clientId: String?

    @Environment(ClientRouter.self) private var router: ClientRouter?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoUploadAfterCapture") private var autoUpload = true
    @State private var camera = CameraController()
    @State private var shots: [UIImage] = []
    @State private var pending: UIImage?
    @State private var month: Period = .current
    @State private var flash = false

    var body: some View {
        ZStack {
            FColor.cameraBg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                viewfinder
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                bottomBar
            }
            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task {
            month = period ?? router?.period ?? .current
            camera.onCapture = { image in
                withAnimation(.easeOut(duration: 0.15)) { flash = true }
                withAnimation(.easeIn(duration: 0.25).delay(0.1)) { flash = false }
                if autoUpload {
                    accept(image)
                } else {
                    pending = image
                }
            }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .sheet(item: Binding(get: { pending.map(IdentifiedImage.init) }, set: { if $0 == nil { pending = nil } })) { item in
            CapturePreview(image: item.image) {
                accept(item.image)
                pending = nil
            } onRetake: {
                pending = nil
            }
        }
    }

    private func accept(_ image: UIImage) {
        shots.append(image)
        UploadQueue.shared.enqueue(image: image, period: month, clientId: clientId)
    }

    private var topBar: some View {
        HStack {
            circleButton(.x) { dismiss() }.accessibilityLabel("Kapat")
            Spacer()
            Menu {
                ForEach(0..<6, id: \.self) { i in
                    let p = Period.current.adding(-i)
                    Button(p.title) { month = p }
                }
            } label: {
                HStack(spacing: 6) {
                    Icon(.calendar, size: 14)
                    Text(month.title)
                }
                .fFont(12.5, .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            Spacer()
            circleButton(camera.torchOn ? .zap : .zapOff) { camera.torchOn.toggle() }
                .accessibilityLabel(camera.torchOn ? "Flaşı kapat" : "Flaşı aç")
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private var viewfinder: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2E3C3A), Color(hex: 0x141C1B)], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 400)
            switch camera.authorization {
            case .authorized:
                CameraPreview(session: camera.session)
                QuadOverlay(quad: camera.quad, stable: camera.stable)
            case .denied:
                VStack(spacing: 12) {
                    Icon(.camera, size: 32)
                    Text("Kamera erişimi kapalı").fFont(16, .heavy)
                    Text("Ayarlar'dan Fişlik için kamerayı aç.").fFont(13, .medium).foregroundStyle(.white.opacity(0.7))
                    Button("Ayarları aç") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.f(.primary, height: 44, fontSize: 14))
                    .frame(width: 180)
                }
                .foregroundStyle(.white)
            case .unknown:
                ProgressView().tint(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) {
            if camera.quad != nil {
                HStack(spacing: 6) {
                    Icon(.check, size: 14)
                    Text(camera.stable ? "Fiş algılandı — sabit tut" : "Fiş algılanıyor…")
                }
                .fFont(12.5, .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background((camera.stable ? FColor.success : Color.black.opacity(0.5)).opacity(0.95), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.top, 16)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: camera.quad != nil)
    }

    private var bottomBar: some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let last = shots.last {
                        Image(uiImage: last).resizable().scaledToFill()
                    } else {
                        Color(hex: 0xF7F7F2).opacity(0.15)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 2))
                if !shots.isEmpty {
                    Text("\(shots.count)")
                        .fFont(12, .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(FColor.brand, in: Capsule())
                        .overlay(Capsule().strokeBorder(FColor.cameraBg, lineWidth: 2))
                        .offset(x: 8, y: -8)
                }
            }
            .opacity(shots.isEmpty ? 0.6 : 1)
            Spacer()
            Button { camera.capture() } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                    .overlay(Circle().fill(.white).frame(width: 62, height: 62).scaleEffect(camera.capturing ? 0.85 : 1))
                    .animation(.easeOut(duration: 0.12), value: camera.capturing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fotoğraf çek")
            Spacer()
            Button("Bitti") { dismiss() }
                .fFont(15, .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(FColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func circleButton(_ icon: FIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 20)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Shown after a capture when "Çekimden sonra otomatik yükle" is off.
private struct CapturePreview: View {
    let image: UIImage
    let onUse: () -> Void
    let onRetake: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Button("Tekrar çek", action: onRetake).buttonStyle(.fSecondary)
                Button("Yükle", action: onUse).buttonStyle(.fPrimary)
            }
        }
        .padding(20)
        .presentationDetents([.large])
    }
}

/// Live camera layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Teal outline around the detected receipt plus a dim mask outside it.
struct QuadOverlay: View {
    let quad: Quad?
    let stable: Bool

    var body: some View {
        GeometryReader { geo in
            if let quad {
                let path = Path { p in
                    let pts = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { convert($0, in: geo.size) }
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                    p.closeSubpath()
                }
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.25))
                        .mask(Rectangle().overlay(path.blendMode(.destinationOut)).compositingGroup())
                    path.stroke(stable ? FColor.success : FColor.brand, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .animation(.easeOut(duration: 0.1), value: quad)
            }
        }
        .allowsHitTesting(false)
    }

    /// Vision normalized (bottom-left origin, portrait buffer) → view coords with aspect-fill.
    private func convert(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let bufferAspect: CGFloat = 3.0 / 4.0
        let viewAspect = size.width / size.height
        var w = size.width, h = size.height, ox: CGFloat = 0, oy: CGFloat = 0
        if viewAspect > bufferAspect {
            h = size.width / bufferAspect
            oy = (size.height - h) / 2
        } else {
            w = size.height * bufferAspect
            ox = (size.width - w) / 2
        }
        return CGPoint(x: ox + p.x * w, y: oy + (1 - p.y) * h)
    }
}

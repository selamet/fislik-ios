import PDFKit
import Photos
import SwiftUI

/// 2Q — full-screen viewer: pinch/zoom, rotate, swipe between receipts, save and share.
struct ReceiptViewer: View {
    let receipts: [Receipt]
    let startId: String
    var initialRotation: Double = 0
    var onChange: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var currentId = ""
    @State private var zoom: CGFloat = 1
    @State private var rotation: Double = 0
    @State private var shareItem: ShareFile?
    @State private var toast: String?

    private var index: Int { receipts.firstIndex { $0.id == currentId } ?? 0 }
    private var current: Receipt? { receipts.indices.contains(index) ? receipts[index] : nil }

    var body: some View {
        ZStack {
            Color(hex: 0x0F1716).ignoresSafeArea()
            TabView(selection: $currentId) {
                ForEach(receipts) { r in
                    ZoomablePage(receipt: r, zoom: r.id == currentId ? $zoom : .constant(1), rotation: r.id == currentId ? rotation : 0)
                        .tag(r.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    glass(.x) { dismiss() }.accessibilityLabel("Kapat")
                    Spacer()
                    Text("\(current?.merchant ?? "") · \(index + 1) / \(receipts.count)").fFont(13, .heavy)
                    Spacer()
                    glass(.share) { Task { await share() } }.accessibilityLabel("Paylaş")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                Spacer()
                VStack(spacing: 12) {
                    Text("İki parmakla yakınlaştır · sağa/sola kaydırarak diğer fişe geç")
                        .fFont(11.5, .semibold).foregroundStyle(.white.opacity(0.7))
                    HStack {
                        HStack(spacing: 6) {
                            glassText("−") { zoom = max(1, zoom - 0.4) }
                            Text("\(Int(zoom * 100))%").fFont(12.5, .heavy).monospacedDigit().frame(minWidth: 48)
                            glassText("+") { zoom = min(5, zoom + 0.4) }
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            glass(.rotateCw) { withAnimation { rotation += 90 } }
                            glass(.download) { Task { await saveToPhotos() } }
                            glass(.chevronLeft) { step(-1) }.opacity(index > 0 ? 1 : 0.4)
                            glass(.chevronRight) { step(1) }.opacity(index < receipts.count - 1 ? 1 : 0.4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
            .foregroundStyle(.white)

            if let toast {
                VStack { FToast(text: toast) { self.toast = nil }; Spacer() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            currentId = startId
            rotation = initialRotation
        }
        .onChange(of: currentId) { _, id in
            zoom = 1
            rotation = 0
            onChange(id)
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func step(_ delta: Int) {
        let i = index + delta
        guard receipts.indices.contains(i) else { return }
        withAnimation { currentId = receipts[i].id }
    }

    private func glass(_ icon: FIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: icon == .x ? 20 : 16)
                .frame(width: icon == .x || icon == .share ? 40 : 38, height: icon == .x || icon == .share ? 40 : 38)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func glassText(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).fFont(18, .heavy)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func share() async {
        guard let r = current, let data = await ReceiptImageLoader.shared.data(for: r) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(r.merchant.slug).\(r.isPDF ? "pdf" : "jpg")")
        try? data.write(to: url)
        shareItem = ShareFile(url: url)
    }

    private func saveToPhotos() async {
        guard let r = current, !r.isPDF, let data = await ReceiptImageLoader.shared.data(for: r), let image = UIImage(data: data) else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            toast = "Fotoğraflar'a kaydetme izni yok."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            toast = "Fotoğraflar'a kaydedildi."
        } catch {
            toast = "Kaydedilemedi."
        }
    }
}

/// One page: image with pinch-to-zoom + pan, or a PDF document.
private struct ZoomablePage: View {
    let receipt: Receipt
    @Binding var zoom: CGFloat
    let rotation: Double
    @State private var image: UIImage?
    @State private var pdf: PDFDocument?
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        Group {
            if let pdf {
                PDFKitView(document: pdf)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(zoom * pinch)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { v, s, _ in s = v.magnification }
                            .onEnded { v in zoom = min(5, max(1, zoom * v.magnification)); if zoom == 1 { offset = .zero; lastOffset = .zero } }
                    )
                    .simultaneousGesture(
                        zoom > 1 ? DragGesture()
                            .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                            .onEnded { _ in lastOffset = offset } : nil
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            zoom = zoom > 1 ? 1 : 2.5
                            if zoom == 1 { offset = .zero; lastOffset = .zero }
                        }
                    }
                    .animation(.spring(duration: 0.25), value: zoom)
                    .animation(.spring(duration: 0.3), value: rotation)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: receipt.id) {
            guard let data = await ReceiptImageLoader.shared.data(for: receipt) else { return }
            if receipt.isPDF { pdf = PDFDocument(data: data) } else { image = UIImage(data: data) }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

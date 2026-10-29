import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 2K — "Fiş Ekle" bottom sheet.
struct AddReceiptSheet: View {
    var clientId: String?
    var periodOverride: Period?
    @Environment(ClientRouter.self) private var router: ClientRouter?
    @Environment(\.dismiss) private var dismiss
    @State private var store = ReceiptStore.shared
    @State private var photos: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var pickingPDF = false
    @State private var showCamera = false

    private var period: Period { periodOverride ?? router?.period ?? .current }
    private var targetPeriod: Period {
        store.state(period).lock.locked ? Period.current : period
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fiş Ekle").fFont(22, .heavy, tracking: -0.4)
                    (Text(targetPeriod.title).fontWeight(.heavy).foregroundColor(FColor.brand)
                     + Text(" ayına eklenecek") + Text(creditsText))
                        .fFont(12.5, .semibold)
                        .foregroundStyle(FColor.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Icon(.x, size: 16).foregroundStyle(FColor.muted)
                        .frame(width: 32, height: 32)
                        .background(FColor.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kapat")
            }

            Button { showCamera = true } label: {
                HStack(spacing: 14) {
                    Icon(.camera, size: 26)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kamera ile çek").fFont(17, .heavy)
                        Text("Arka arkaya çek; her fiş anında yüklenir ve analiz edilir.").fFont(12.5, .medium).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 18)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(FColor.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: FColor.brand.opacity(0.5), radius: 16, y: 12)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                tile(icon: .images, tint: FColor.brand, title: "Galeriden seç", subtitle: "Birden fazla fotoğraf seçebilirsin") { pickingPhotos = true }
                tile(icon: .fileText, tint: FColor.info, title: "PDF yükle", subtitle: "e-Fatura / e-Arşiv · Dosyalar'dan") { pickingPDF = true }
            }

            HStack(spacing: 8) {
                Icon(.zap, size: 14)
                Text("Fotoğraflar yüklemeden önce otomatik sıkıştırılır")
            }
            .fFont(12, .semibold)
            .foregroundStyle(FColor.muted)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .background(FColor.bg.ignoresSafeArea())
        .fSelfSizingSheet()
        .photosPicker(isPresented: $pickingPhotos, selection: $photos, maxSelectionCount: 30, matching: .images, preferredItemEncoding: .compatible)
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { UploadQueue.shared.enqueue(pdfURL: url, period: targetPeriod, clientId: clientId) }
                dismiss()
            }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            let period = targetPeriod
            Task {
                for (i, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let name = item.itemIdentifier.map { "IMG_\($0.prefix(4)).jpg" } ?? "IMG_\(i + 1).jpg"
                        UploadQueue.shared.enqueue(imageData: data, filename: name, period: period, clientId: clientId)
                    }
                }
                photos = []
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: { dismiss() }) {
            CameraScreen(period: targetPeriod, clientId: clientId)
        }
    }

    private var creditsText: String {
        guard let c = store.credits, !c.unlimited, let limit = c.limit else { return "" }
        return " · Bu ay \(c.used)/\(limit) analiz"
    }

    private func tile(icon: FIcon, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                FIconTile(icon: icon, size: 42, iconSize: 20, tint: tint, background: tint.opacity(tint == FColor.info ? 0.08 : 0.1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fFont(14.5, .heavy).foregroundStyle(FColor.ink)
                    Text(subtitle).fFont(12, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.leading).lineSpacing(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fCard(radius: 18)
        }
        .buttonStyle(.plain)
    }
}

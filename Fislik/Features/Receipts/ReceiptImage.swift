import PDFKit
import SwiftUI

/// Loads receipt images by receipt id (presigned URLs change on every list fetch),
/// caching in memory and on disk. PDFs are rendered to a first-page thumbnail.
actor ReceiptImageLoader {
    static let shared = ReceiptImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() { memory.countLimit = 120 }

    func image(for receipt: Receipt) async -> UIImage? {
        let key = receipt.id as NSString
        if let img = memory.object(forKey: key) { return img }
        if let task = inflight[receipt.id] { return await task.value }
        let task = Task<UIImage?, Never> { [dir] in
            let file = dir.appendingPathComponent(receipt.id + (receipt.isPDF ? ".pdf" : ".img"))
            var data = try? Data(contentsOf: file)
            if data == nil, let url = receipt.imageUrl {
                data = try? await URLSession.shared.data(from: url).0
                if let data { try? data.write(to: file, options: .atomic) }
            }
            guard let data else { return nil }
            if receipt.isPDF {
                return PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
            }
            return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 900, height: 1200))
        }
        inflight[receipt.id] = task
        let img = await task.value
        inflight[receipt.id] = nil
        if let img { memory.setObject(img, forKey: key) }
        return img
    }

    /// Full-resolution data for the viewer / sharing.
    func data(for receipt: Receipt) async -> Data? {
        let file = dir.appendingPathComponent(receipt.id + (receipt.isPDF ? ".pdf" : ".img"))
        if let d = try? Data(contentsOf: file) { return d }
        guard let url = receipt.imageUrl, let d = try? await URLSession.shared.data(from: url).0 else { return nil }
        try? d.write(to: file, options: .atomic)
        return d
    }

    func store(_ data: Data, for receiptId: String, pdf: Bool) {
        try? data.write(to: dir.appendingPathComponent(receiptId + (pdf ? ".pdf" : ".img")), options: .atomic)
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// Thumbnail with the soft teal gradient placeholder and a paper receipt while loading.
struct ReceiptThumb: View {
    let receipt: Receipt
    var contentMode: ContentMode = .fill
    var showPaper = true
    /// Solid backdrop instead of the soft gradient (detail header uses the design's #2a3937).
    var backdrop: Color?
    var alignment: Alignment = .center
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: alignment) {
            if let backdrop {
                backdrop
            } else {
                LinearGradient(colors: [Color(light: 0xEEF3F2, dark: 0x1A2524), Color(light: 0xDDE5E2, dark: 0x22302E)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let image, alignment == .top {
                // Width-filling, top-anchored page (PDF header): the bottom is cropped, never the top.
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width)
                }
                .transition(.opacity)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .transition(.opacity)
            } else if showPaper {
                ReceiptPaper(merchant: receipt.extraction?.merchantName ?? "", total: receipt.total.map(TR.plain) ?? "")
                    .scaleEffect(0.9)
                    .offset(y: 10)
            }
        }
        .clipped()
        .task(id: receipt.id) {
            let img = await ReceiptImageLoader.shared.image(for: receipt)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

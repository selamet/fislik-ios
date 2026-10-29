import Foundation
import Observation
import UIKit

struct UploadItem: Codable, Identifiable, Equatable {
    enum State: String, Codable {
        case queued, compressing, waitingNetwork, uploading, finishing, done, failed
    }

    let id: String
    var filename: String
    var period: Period
    var contentType: String
    /// True until the original image has been converted to JPEG.
    var needsCompression: Bool
    var state: State = .queued
    var progress: Double = 0
    var receiptId: String?
    var uploadURL: URL?
    var error: String?
    var attempts = 0
    var clientId: String?
    var createdAt = Date()

    var isDone: Bool { state == .done }
    var isActive: Bool { state != .done && state != .failed }

    var statusLabel: String {
        switch state {
        case .queued: "Sırada"
        case .compressing: "Sıkıştırılıyor"
        case .waitingNetwork: "Bağlantı bekleniyor"
        case .uploading: "Yükleniyor · %\(Int(progress * 100))"
        case .finishing: "Tamamlanıyor"
        case .done: "Yüklendi"
        case .failed: "Hata — Tekrar dene"
        }
    }
}

/// Persistent upload pipeline: compress → POST /receipts/uploads → background PUT → POST /complete.
/// Items and their files live in Application Support, so captures survive offline periods and app restarts.
@MainActor
@Observable
final class UploadQueue {
    static let shared = UploadQueue()

    private(set) var items: [UploadItem] = []
    /// Last user-facing notice, e.g. the month the server actually filed a receipt into.
    var notice: String?
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private let maxConcurrent = 2

    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {
        if let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
           let saved = try? JSONDecoder().decode([UploadItem].self, from: data) {
            items = saved.filter { $0.state != .done }.map { item in
                var i = item
                if [.compressing, .uploading, .finishing].contains(i.state) { i.state = .queued }
                return i
            }
        }
        UploadTransport.shared.onProgress = { [weak self] id, p in
            Task { @MainActor in self?.update(id) { $0.progress = p } }
        }
        UploadTransport.shared.onFinish = { [weak self] id, status, error in
            Task { @MainActor in await self?.transportFinished(id: id, status: status, error: error) }
        }
        Connectivity.shared.onReconnect { [weak self] in self?.pump() }
        pump()
    }

    func items(for period: Period) -> [UploadItem] {
        items.filter { $0.period == period }
    }

    var activeCount: Int { items.filter(\.isActive).count }

    // MARK: Enqueue

    func enqueue(imageData: Data, filename: String, period: Period, clientId: String? = nil) {
        add(data: imageData, filename: filename, contentType: "image/jpeg", needsCompression: true, period: period, clientId: clientId)
    }

    func enqueue(image: UIImage, period: Period, clientId: String? = nil) {
        guard let data = ImageCompressor.jpeg(from: image) else { return }
        let name = "IMG_\(Int(Date().timeIntervalSince1970) % 10000).jpg"
        add(data: data, filename: name, contentType: "image/jpeg", needsCompression: false, period: period, clientId: clientId)
    }

    func enqueue(pdfURL: URL, period: Period, clientId: String? = nil) {
        let scoped = pdfURL.startAccessingSecurityScopedResource()
        defer { if scoped { pdfURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: pdfURL) else { return }
        add(data: data, filename: pdfURL.lastPathComponent, contentType: "application/pdf", needsCompression: false, period: period, clientId: clientId)
    }

    private func add(data: Data, filename: String, contentType: String, needsCompression: Bool, period: Period, clientId: String?) {
        let id = UUID().uuidString
        try? data.write(to: fileURL(id), options: .atomic)
        var item = UploadItem(id: id, filename: filename, period: period, contentType: contentType, needsCompression: needsCompression, clientId: clientId)
        if data.count > ImageCompressor.maxUploadBytes && !needsCompression {
            item.state = .failed
            item.error = "Dosya çok büyük (en fazla 15 MB)."
        }
        items.insert(item, at: 0)
        save()
        pump()
    }

    // MARK: Control

    func retry(_ id: String) {
        update(id) {
            $0.state = .queued
            $0.error = nil
            $0.progress = 0
            $0.uploadURL = nil
        }
        pump()
    }

    func cancel(_ id: String) {
        UploadTransport.shared.cancel(id)
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
        running.remove(id)
        save()
    }

    func retryAllFailed() {
        for item in items where item.state == .failed { retry(item.id) }
    }

    /// Starts as many queued items as allowed.
    func pump() {
        let online = Connectivity.shared.isOnline
        for i in items.indices where items[i].state == .waitingNetwork && online {
            items[i].state = .queued
        }
        for item in items.reversed() where item.state == .queued && running.count < maxConcurrent && !running.contains(item.id) {
            if !online {
                update(item.id) { $0.state = .waitingNetwork }
                continue
            }
            running.insert(item.id)
            Task { await process(item.id) }
        }
    }

    // MARK: Pipeline

    private func process(_ id: String) async {
        guard var item = items.first(where: { $0.id == id }) else { running.remove(id); return }
        let file = fileURL(id)

        if item.needsCompression {
            update(id) { $0.state = .compressing; $0.progress = 0.05 }
            let compressed = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: file)).flatMap(ImageCompressor.jpeg(from:))
            }.value
            guard let compressed else { return fail(id, "Görsel okunamadı.") }
            try? compressed.write(to: file, options: .atomic)
            update(id) { $0.needsCompression = false; $0.contentType = "image/jpeg" }
            item = items.first { $0.id == id } ?? item
        }

        do {
            update(id) { $0.state = .uploading; $0.progress = 0.08 }
            let ticket = try await API.createUpload(contentType: item.contentType, period: item.period, clientId: item.clientId)
            update(id) {
                $0.receiptId = ticket.receiptId
                $0.uploadURL = ticket.uploadUrl
            }
            save()
            UploadTransport.shared.put(id: id, file: file, to: ticket.uploadUrl, contentType: item.contentType)
        } catch let e as APIError {
            if e == .offline {
                update(id) { $0.state = .waitingNetwork }
                running.remove(id)
            } else {
                fail(id, e.message)
            }
        } catch {
            fail(id, APIError.transport(code: 0).message)
        }
    }

    private func transportFinished(id: String, status: Int?, error: URLError?) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if let error {
            if error.code == .cancelled { return }
            if [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
                update(id) { $0.state = .waitingNetwork }
                running.remove(id)
                return
            }
            return fail(id, APIClient.map(error).message)
        }
        guard let status, (200..<300).contains(status) else {
            // Presigned URL expired: ask for a fresh one once.
            if status == 403 && item.attempts < 1 {
                update(id) { $0.attempts += 1; $0.uploadURL = nil }
                await process(id)
                return
            }
            return fail(id, "Yükleme başarısız (\(status ?? 0)).")
        }
        update(id) { $0.state = .finishing; $0.progress = 1 }
        guard let receiptId = item.receiptId else { return fail(id, "Yükleme başarısız.") }
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(id).path)[.size] as? Int) ?? nil
            let receipt = try await API.completeUpload(receiptId: receiptId, size: size)
            if let data = try? Data(contentsOf: fileURL(id)) {
                await ReceiptImageLoader.shared.store(data, for: receipt.id, pdf: receipt.isPDF)
            }
            if receipt.period != item.period.raw, let actual = Period(receipt.period) {
                notice = "\(item.period.title) kapalı olduğu için fiş \(actual.title) ayına eklendi."
            }
            if item.clientId == nil { ReceiptStore.shared.upsert(receipt) }
            update(id) { $0.state = .done }
            running.remove(id)
            try? FileManager.default.removeItem(at: fileURL(id))
            save()
            Task { await ReceiptStore.shared.refreshCredits() }
            LocalNotifier.uploadFinished(remaining: activeCount)
            try? await Task.sleep(for: .seconds(1.5))
            items.removeAll { $0.id == id }
            save()
            pump()
        } catch let e as APIError {
            fail(id, e.message)
        } catch {
            fail(id, APIError.transport(code: 0).message)
        }
    }

    private func fail(_ id: String, _ message: String) {
        update(id) {
            $0.state = .failed
            $0.error = message
        }
        running.remove(id)
        save()
        pump()
    }

    // MARK: Storage

    private func update(_ id: String, _ change: (inout UploadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private func fileURL(_ id: String) -> URL { dir.appendingPathComponent(id) }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }

    func clearAll() {
        for item in items { UploadTransport.shared.cancel(item.id) }
        items = []
        running = []
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// Background URLSession for the R2 PUTs, so uploads continue while the app is suspended.
final class UploadTransport: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = UploadTransport()
    static let identifier = "dev.selamet.fislik.uploads"

    var onProgress: ((String, Double) -> Void)?
    var onFinish: ((String, Int?, URLError?) -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func put(id: String, file: URL, to url: URL, contentType: String) {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: req, fromFile: file)
        task.taskDescription = id
        task.resume()
    }

    func cancel(_ id: String) {
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let id = task.taskDescription, totalBytesExpectedToSend > 0 else { return }
        let p = 0.08 + 0.9 * Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress?(id, min(p, 0.98))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        onFinish?(id, status, error as? URLError)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            BackgroundSessionEvents.shared.completionHandler?()
            BackgroundSessionEvents.shared.completionHandler = nil
        }
    }
}

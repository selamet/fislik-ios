#if DEBUG
import UIKit

/// Debug-only in-process API that serves the design's sample data.
/// Launch with `-demo client` or `-demo accountant`; nothing leaves the device.
enum DemoMode {
    static var role: UserRole? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return nil }
        return UserRole(rawValue: args[i + 1])
    }

    static var isOn: Bool { role != nil }
    static let token = "demo-token"

    static func install() {
        guard isOn else { return }
        URLProtocol.registerClass(DemoURLProtocol.self)
    }
}

final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == APIConfig.baseURL.host || host == "demo.fislik.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (status, body, type) = DemoData.shared.respond(method: request.httpMethod ?? "GET", url: url, body: request.bodyData)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        // Small delay so loading states are visible but screenshots stay fast.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// Mutable sample dataset mirroring `fislik-shared.js` from the design.
final class DemoData: @unchecked Sendable {
    static let shared = DemoData()
    private let lock = NSLock()

    struct R {
        var id, merchant, legal: String
        var day: Int
        var total, vat: String
        var rates: [(Int, String)]
        var doc: String
        var processed: Bool
        var issue: String?
        var cat, pay: String
        var monthOffset = 0
        var pdf = false
        var dateMonthOffset = 0
        var byAccountant = false
        var status = "done"
        var taxId: String?
        var office: String?
        var number: String?
    }

    private var receipts: [R] = [
        R(id: "r1", merchant: "Migros", legal: "Migros Ticaret A.Ş.", day: 24, total: "1482.35", vat: "246.52", rates: [(20, "198.12"), (10, "48.40")], doc: "fis", processed: true, cat: "market", pay: "kredi_karti", taxId: "6220529513", office: "Büyük Mükellefler", number: "0042"),
        R(id: "r2", merchant: "Shell", legal: "Shell & Turcas Petrol A.Ş.", day: 23, total: "2350.00", vat: "391.67", rates: [(20, "391.67")], doc: "fis", processed: true, cat: "yakit", pay: "kredi_karti", taxId: "8150034725", office: "Boğaziçi", number: "1187"),
        R(id: "r3", merchant: "Trendyol", legal: "DSM Grup Danışmanlık İletişim ve Satış Tic. A.Ş.", day: 22, total: "899.90", vat: "149.98", rates: [(20, "149.98")], doc: "fatura", processed: false, issue: "Bu fatura şirket adına mı kesilmiş? VKN görünmüyor.", cat: "ofis", pay: "kredi_karti", office: "Maslak", number: "EAR2026000012345"),
        R(id: "r4", merchant: "A101", legal: "A101 Yeni Mağazacılık A.Ş.", day: 21, total: "236.70", vat: "21.52", rates: [(10, "21.52")], doc: "fis", processed: false, cat: "market", pay: "nakit", number: "3321"),
        R(id: "r5", merchant: "Starbucks", legal: "Shaya Kahve A.Ş.", day: 19, total: "310.00", vat: "28.18", rates: [(10, "28.18")], doc: "fis", processed: false, cat: "yemek", pay: "kredi_karti", dateMonthOffset: -1, number: "8812"),
        R(id: "r6", merchant: "Türk Telekom", legal: "Türk Telekomünikasyon A.Ş.", day: 15, total: "489.00", vat: "81.50", rates: [(20, "81.50")], doc: "fatura", processed: true, cat: "iletisim", pay: "bilinmiyor", pdf: true, byAccountant: true, taxId: "8760047021", office: "Ulus", number: "TTK2026000889912"),
        R(id: "r7", merchant: "Getir", legal: "Getir Perakende Lojistik A.Ş.", day: 12, total: "164.50", vat: "14.95", rates: [(10, "14.95")], doc: "fis", processed: false, cat: "market", pay: "kredi_karti", number: "5520"),
        R(id: "r8", merchant: "Getir", legal: "Getir Perakende Lojistik A.Ş.", day: 12, total: "164.50", vat: "14.95", rates: [(10, "14.95")], doc: "fis", processed: false, cat: "market", pay: "kredi_karti", number: "5520"),
        R(id: "p1", merchant: "Migros", legal: "Migros Ticaret A.Ş.", day: 30, total: "612.40", vat: "55.67", rates: [(10, "55.67")], doc: "fis", processed: true, cat: "market", pay: "kredi_karti", monthOffset: -1),
        R(id: "p2", merchant: "Migros Jet", legal: "Migros Ticaret A.Ş.", day: 12, total: "96.50", vat: "8.77", rates: [(10, "8.77")], doc: "fis", processed: true, cat: "market", pay: "nakit", monthOffset: -1),
    ]
    private var readIds: Set<String> = ["n3", "n4", "n5", "n6"]
    private var locked: Set<String> = []
    private var sentAt: [String: Date] = [:]
    private var grants: [[String: Any]] = [
        ["id": "g1", "status": "active", "invited_email": "zeynep@kayamusavirlik.com", "direction": "outgoing", "counterpart_name": "Zeynep Kaya", "counterpart_email": "zeynep@kayamusavirlik.com", "invited_role": "accountant"],
        ["id": "g2", "status": "pending", "invited_email": "ayse@yildirimticaret.com", "direction": "incoming", "counterpart_name": "Mehmet Demir", "counterpart_email": "mehmet@demirmusavirlik.com", "invited_role": "client"],
        ["id": "g3", "status": "pending", "invited_email": "ali@ozturkmusavirlik.com", "direction": "outgoing", "counterpart_name": NSNull(), "counterpart_email": "ali@ozturkmusavirlik.com", "invited_role": "accountant"],
    ]

    private var current: Period { .current }

    private func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: d)
    }

    private func date(day: Int, monthOffset: Int, hour: Int = 14) -> Date {
        let p = current.adding(monthOffset)
        let today = Calendar.fislik.component(.day, from: Date())
        let d = monthOffset == 0 ? min(day, today) : day
        return Calendar.fislik.date(from: DateComponents(year: p.year, month: p.month, day: d, hour: hour, minute: 3)) ?? Date()
    }

    private func json(_ r: R) -> [String: Any] {
        let period = current.adding(r.monthOffset)
        let receiptDate = date(day: r.day, monthOffset: r.monthOffset + r.dateMonthOffset)
        var extraction: [String: Any] = [
            "status": r.status, "merchant_name": r.merchant, "merchant_legal_name": r.legal,
            "receipt_date": DateParsing.dayString(receiptDate), "total_amount": r.total, "vat_total": r.vat,
            "vat_breakdown": r.rates.map { ["rate": $0.0, "amount": $0.1] }, "doc_type": r.doc,
            "merchant_tax_id": r.taxId ?? NSNull(), "merchant_tax_id_type": r.taxId == nil ? NSNull() : "vkn",
            "merchant_tax_office": r.office ?? NSNull(), "receipt_number": r.number ?? NSNull(),
            "payment_method": r.pay, "expense_category": r.cat, "edited": r.id == "r3",
        ]
        if r.status == "pending" { extraction["merchant_name"] = NSNull() }
        return [
            "id": r.id, "period": period.raw, "created_at": iso(date(day: r.day, monthOffset: r.monthOffset)),
            "image_url": "https://demo.fislik.local/img/\(r.id)", "content_type": r.pdf ? "application/pdf" : "image/jpeg",
            "processed": r.processed,
            "open_issue": r.issue.map { ["id": "i-\(r.id)", "message": $0, "author_name": "Zeynep Kaya", "created_at": iso(Date().addingTimeInterval(-3600 * 5))] } ?? NSNull(),
            "extraction": extraction, "uploaded_by": r.byAccountant ? "acc-1" : NSNull(),
        ]
    }

    private func month(_ raw: String?) -> [R] {
        receipts.filter { current.adding($0.monthOffset).raw == raw }
    }

    private func summary(_ rs: [R]) -> [String: Any] {
        var byRate: [String: Decimal] = [:]
        var total: Decimal = 0, vat: Decimal = 0
        for r in rs {
            total += Decimal(string: r.total)!
            vat += Decimal(string: r.vat)!
            for (rate, amount) in r.rates { byRate["\(rate)", default: 0] += Decimal(string: amount)! }
        }
        return ["receipt_count": rs.count, "analyzed_count": rs.count, "total_amount": "\(total)", "vat_total": "\(vat)",
                "vat_by_rate": byRate.mapValues { "\($0)" }, "payment_method_totals": [:], "category_totals": [:]]
    }

    private var notifications: [[String: Any]] {
        let p = current.raw, prev = current.previous.raw
        let items: [(String, String, [String: Any], Date)] = [
            ("n1", "issue_opened", ["receipt_id": "r3", "period": p, "message": "Bu fatura şirket adına mı kesilmiş?"], Date().addingTimeInterval(-3600 * 2)),
            ("n2", "receipts_processed", ["period": p, "accountant_name": "Zeynep Kaya", "processed_count": 3], Date().addingTimeInterval(-3600 * 6)),
            ("n3", "receipts_processed", ["period": prev, "accountant_name": "Zeynep Kaya", "processed_count": 21], Date().addingTimeInterval(-86400 * 26)),
            ("n4", "period_locked", ["period": prev, "accountant_name": "Zeynep Kaya"], Date().addingTimeInterval(-86400 * 26 + 120)),
            ("n5", "receipts_submitted", ["client_id": "c1", "client_name": "Ayşe Yıldırım", "period": p, "receipt_count": 8], Date().addingTimeInterval(-86400 * 3)),
            ("n6", "invite_accepted", ["name": "Zeynep Kaya", "role": "accountant"], Date().addingTimeInterval(-86400 * 76)),
        ]
        return items.map { id, type, payload, d in
            ["id": id, "type": type, "payload": payload, "read": readIds.contains(id), "created_at": iso(d)]
        }
    }

    func respond(method: String, url: URL, body: Data?) -> (Int, Data, String) {
        lock.lock()
        defer { lock.unlock() }
        if url.host == "demo.fislik.local" {
            let id = url.lastPathComponent
            let r = receipts.first { $0.id == id }
            if r?.pdf == true { return (200, DemoArt.pdf(for: r!), "application/pdf") }
            return (200, DemoArt.receiptImage(merchant: r?.merchant ?? "FİŞ", total: r?.total ?? "0", rotation: id.hashValue % 3), "image/jpeg")
        }
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let period = query.first { $0.name == "period" }?.value
        let role = DemoMode.role ?? .client
        let bodyJSON = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        func ok(_ obj: Any, _ status: Int = 200) -> (Int, Data, String) {
            (status, (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), "application/json")
        }
        let none: (Int, Data, String) = (204, Data(), "application/json")

        switch (method, path) {
        case ("GET", "/auth/me"):
            return ok(role == .accountant
                      ? ["id": "acc-1", "email": "zeynep@kayamusavirlik.com", "full_name": "Zeynep Kaya", "role": "accountant", "impersonated": false]
                      : ["id": "c1", "email": "ayse@yildirimticaret.com", "full_name": "Ayşe Yıldırım", "role": "client", "impersonated": false])
        case ("GET", "/receipts"), ("GET", "/clients/c1/receipts"):
            return ok(month(period).map(json))
        case ("GET", "/receipts/summary"):
            return ok(summary(month(period)))
        case ("GET", "/receipts/period-lock"):
            return ok(["locked": locked.contains(period ?? "") || period == current.adding(-2).raw, "locked_at": iso(Date().addingTimeInterval(-86400 * 20))])
        case ("GET", "/receipts/submission"):
            let sent = sentAt[period ?? ""] ?? (period == current.previous.raw ? Date().addingTimeInterval(-86400 * 27) : nil)
            return ok(["last_sent_at": sent.map(iso) ?? NSNull(), "can_send": sent == nil, "active_receipt_count": month(period).count, "has_accountant": true])
        case ("POST", "/receipts/submit"):
            sentAt[bodyJSON["period"] as? String ?? ""] = Date()
            return ok(["last_sent_at": iso(Date()), "can_send": false, "active_receipt_count": month(bodyJSON["period"] as? String).count, "has_accountant": true])
        case ("GET", "/credits/me"):
            return ok(["limit": 50, "used": 12, "remaining": 38, "unlimited": false])
        case ("GET", "/grants"):
            return ok(role == .accountant ? [] : grants)
        case ("GET", "/company"), ("GET", "/clients/c1/company"):
            return ok(["full_name": "Ayşe Yıldırım", "trade_name": "Yıldırım Ticaret Ltd. Şti.", "tax_office": "Kadıköy", "tax_number": "1234567890",
                       "national_id": NSNull(), "business_address": "Caferağa Mah. Moda Cad. No:12 Kadıköy/İstanbul", "tax_type": "Gelir Vergisi",
                       "activity_code": "47.11.01", "activity_name": "Perakende gıda satışı", "started_on": "2021-03-01", "updated_at": iso(Date())])
        case ("GET", "/notifications"):
            let items = notifications
            return ok(["unread_count": items.filter { !($0["read"] as! Bool) }.count, "items": items])
        case ("POST", "/notifications/read"):
            if let ids = bodyJSON["ids"] as? [String] { readIds.formUnion(ids) } else { readIds.formUnion(notifications.map { $0["id"] as! String }) }
            return none
        case ("GET", "/notifications/preferences"):
            return ok(["issue_opened": true, "receipts_processed": true, "period_locked": true, "grant_events": false, "month_end_reminder": true, "weekly_digest": false])
        case ("GET", "/clients"):
            let rs = month(period)
            return ok([
                ["client_id": "c1", "full_name": "Ayşe Yıldırım", "receipt_count": rs.count, "unprocessed_count": rs.filter { !$0.processed }.count, "last_upload_at": iso(date(day: 24, monthOffset: 0))],
                ["client_id": "c2", "full_name": "Mehmet Demir", "receipt_count": 23, "unprocessed_count": 0, "last_upload_at": iso(date(day: 22, monthOffset: 0))],
                ["client_id": "c3", "full_name": "Elif Şahin", "receipt_count": 12, "unprocessed_count": 12, "last_upload_at": iso(date(day: 20, monthOffset: 0))],
                ["client_id": "c4", "full_name": "Can Öztürk", "receipt_count": 3, "unprocessed_count": 1, "last_upload_at": iso(date(day: 11, monthOffset: 0))],
                ["client_id": "c5", "full_name": "Deniz Arslan", "receipt_count": 0, "unprocessed_count": 0, "last_upload_at": NSNull()],
            ])
        default:
            break
        }

        if method == "POST", path.hasPrefix("/clients/c1/receipts/"), path.hasSuffix("/processed") {
            let id = url.deletingLastPathComponent().lastPathComponent
            if let i = receipts.firstIndex(where: { $0.id == id }) { receipts[i].processed = true }
            return none
        }
        if method == "DELETE", path.hasPrefix("/clients/c1/receipts/"), path.hasSuffix("/processed") {
            let id = url.deletingLastPathComponent().lastPathComponent
            if let i = receipts.firstIndex(where: { $0.id == id }) { receipts[i].processed = false }
            return none
        }
        if method == "POST", path == "/clients/c1/receipts/processed" {
            for i in receipts.indices where current.adding(receipts[i].monthOffset).raw == bodyJSON["period"] as? String { receipts[i].processed = true }
            return ok(["marked": 1])
        }
        if path.hasPrefix("/clients/c1/periods/") {
            let p = url.deletingLastPathComponent().lastPathComponent
            if method == "POST" { locked.insert(p) } else { locked.remove(p) }
            return method == "POST" ? ok(["locked": true, "locked_at": iso(Date())]) : none
        }
        if method == "DELETE", path.hasPrefix("/receipts/") {
            receipts.removeAll { $0.id == url.lastPathComponent }
            return none
        }
        if method == "POST", path.hasPrefix("/issues/") {
            for i in receipts.indices where "i-\(receipts[i].id)" == url.deletingLastPathComponent().lastPathComponent { receipts[i].issue = nil }
            return none
        }
        if method == "POST", path.hasSuffix("/accept") || path.hasSuffix("/decline") {
            let id = url.deletingLastPathComponent().lastPathComponent
            if let i = grants.firstIndex(where: { $0["id"] as? String == id }) {
                if path.hasSuffix("/accept") { grants[i]["status"] = "active" } else { grants.remove(at: i) }
            }
            return path.hasSuffix("/accept") ? ok(grants.first { $0["id"] as? String == id } ?? [:]) : none
        }
        return ok(["detail": "Demo modunda desteklenmiyor"], 404)
    }
}

/// Draws paper-receipt images so thumbnails and the viewer look realistic.
enum DemoArt {
    static func receiptImage(merchant: String, total: String, rotation: Int) -> Data {
        let size = CGSize(width: 900, height: 1200)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.16, green: 0.22, blue: 0.21, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let paper = CGRect(x: 170, y: 110, width: 560, height: 980)
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: CGFloat(rotation - 1) * 0.03)
            ctx.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(roundedRect: paper, cornerRadius: 6).fill()
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .heavy), .foregroundColor: UIColor.black, .paragraphStyle: center]
            let small: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular), .foregroundColor: UIColor.darkGray]
            let big: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 36, weight: .heavy), .foregroundColor: UIColor.black]
            (merchant.uppercased(with: TR.locale) as NSString).draw(in: CGRect(x: paper.minX, y: paper.minY + 60, width: paper.width, height: 60), withAttributes: title)
            var y = paper.minY + 180
            for (item, price) in [("ÜRÜN 1", "58,90"), ("ÜRÜN 2", "15,00"), ("ÜRÜN 3", "789,00"), ("ÜRÜN 4", "42,50")] {
                (item as NSString).draw(at: CGPoint(x: paper.minX + 50, y: y), withAttributes: small)
                (price as NSString).draw(at: CGPoint(x: paper.maxX - 150, y: y), withAttributes: small)
                y += 50
            }
            UIColor.lightGray.setFill()
            UIRectFill(CGRect(x: paper.minX + 40, y: y + 20, width: paper.width - 80, height: 2))
            ("TOPLAM" as NSString).draw(at: CGPoint(x: paper.minX + 50, y: y + 50), withAttributes: big)
            (TR.plain(Decimal(string: total) ?? 0) as NSString).draw(at: CGPoint(x: paper.maxX - 250, y: y + 50), withAttributes: big)
        }
        return img.jpegData(compressionQuality: 0.8) ?? Data()
    }

    static func pdf(for r: DemoData.R) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            ctx.beginPage()
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let reg: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.darkGray]
            (r.merchant.uppercased(with: TR.locale) as NSString).draw(at: CGPoint(x: 48, y: 60), withAttributes: bold)
            ("e-FATURA · \(r.legal) · VKN \(r.taxId ?? "")" as NSString).draw(at: CGPoint(x: 48, y: 92), withAttributes: reg)
            ("Fatura No: \(r.number ?? "")" as NSString).draw(at: CGPoint(x: 48, y: 140), withAttributes: reg)
            ("Fiber İnternet 100 Mbps          407,50" as NSString).draw(at: CGPoint(x: 48, y: 200), withAttributes: reg)
            ("KDV %20                          81,50" as NSString).draw(at: CGPoint(x: 48, y: 224), withAttributes: reg)
            ("ÖDENECEK TUTAR   \(TR.plain(Decimal(string: r.total) ?? 0)) TL" as NSString).draw(at: CGPoint(x: 48, y: 270), withAttributes: bold)
        }
    }
}
#endif

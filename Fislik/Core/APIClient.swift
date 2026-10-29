import Foundation

enum APIConfig {
    static let baseURL = URL(string: "https://fislik-api.selamet.dev")!
    static let webURL = URL(string: "https://fislik.selamet.dev")!
}

/// Errors surfaced to the UI. `message` is always user-facing Turkish copy.
enum APIError: Error, Equatable, LocalizedError {
    case offline
    case transport(code: Int)
    case unauthorized
    case server(status: Int, detail: String?)
    case decoding

    var status: Int? {
        if case .server(let status, _) = self { return status }
        if case .unauthorized = self { return 401 }
        return nil
    }

    var detail: String? {
        if case .server(_, let detail) = self { return detail }
        return nil
    }

    /// Server `detail` strings that are already Turkish and safe to show verbatim.
    static let turkishDetails: Set<String> = [
        "Bu ay muhasebeciniz tarafından kapatıldı.",
        "Bağlı muhasebeciniz yok",
        "Bu ay zaten gönderildi",
        "Aylık analiz limiti doldu",
        "Dosya çok büyük (en fazla 15 MB).",
    ]

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .offline: return "İnternet bağlantısı yok."
        case .transport: return "Sunucuya ulaşılamadı. Bağlantını kontrol edip tekrar dene."
        case .unauthorized: return "Oturumun sona ermiş, tekrar giriş yap."
        case .decoding: return "Beklenmeyen bir yanıt alındı."
        case .server(let status, let detail):
            if let detail, Self.turkishDetails.contains(detail) { return detail }
            switch status {
            case 400: return "İstek geçersiz."
            case 403: return "Bu işlem için yetkin yok."
            case 404: return "Kayıt bulunamadı."
            case 409: return "Bu işlem zaten yapılmış."
            case 413: return "Dosya çok büyük (en fazla 15 MB)."
            case 422: return "Girilen bilgiler geçersiz."
            case 429: return "Çok fazla deneme. Biraz sonra tekrar dene."
            case 500...: return "Sunucuda bir sorun oluştu."
            default: return "Bir şeyler ters gitti."
            }
        }
    }

    /// Code shown on the error screen ("Hata kodu: NET-503").
    var code: String {
        switch self {
        case .offline: "NET-0"
        case .transport(let code): "NET-\(abs(code))"
        case .unauthorized: "AUTH-401"
        case .server(let status, _): "NET-\(status)"
        case .decoding: "DEC-1"
        }
    }
}

enum HTTPMethod: String {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}

/// Thin async JSON client. Auth is a Bearer JWT; cookies are disabled so the
/// cookie the API also sets can never shadow the header.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    var tokenProvider: () -> String? = { nil }
    /// Called on any 401 so the app can show the session-expired banner.
    var onUnauthorized: () -> Void = {}

    let session: URLSession
    let baseURL: URL

    init(baseURL: URL = APIConfig.baseURL, configuration: URLSessionConfiguration = .default) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.baseURL = baseURL
    }

    // MARK: Coding

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = DateParsing.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(DateParsing.dayString(date))
        }
        return e
    }()

    // MARK: Requests

    func request<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String?] = [:],
        body: (some Encodable)? = EmptyBody?.none,
        authorized: Bool = true
    ) async throws -> Response {
        let data = try await raw(method, path, query: query, body: body, authorized: authorized)
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        do {
            return try Self.decoder.decode(Response.self, from: DecimalNormalizer.normalize(data))
        } catch {
            #if DEBUG
            print("Decoding \(Response.self) failed: \(error)")
            #endif
            throw APIError.decoding
        }
    }

    func send(_ method: HTTPMethod, _ path: String, query: [String: String?] = [:], body: (some Encodable)? = EmptyBody?.none) async throws {
        _ = try await raw(method, path, query: query, body: body, authorized: true)
    }

    func raw(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String?] = [:],
        body: (some Encodable)?,
        authorized: Bool
    ) async throws -> Data {
        let req = try makeRequest(method, path, query: query, body: body, authorized: authorized)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            throw Self.map(error)
        }
        try validate(response, data: data, authorized: authorized)
        return data
    }

    /// Downloads a binary resource (e.g. receipts.zip) to a temporary file.
    func download(_ path: String, query: [String: String?] = [:], filename: String) async throws -> URL {
        let req = try makeRequest(.get, path, query: query, body: EmptyBody?.none, authorized: true)
        let (tmp, response): (URL, URLResponse)
        do {
            (tmp, response) = try await session.download(for: req)
        } catch let error as URLError {
            throw Self.map(error)
        }
        try validate(response, data: (try? Data(contentsOf: tmp)) ?? Data(), authorized: true)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    func makeRequest(_ method: HTTPMethod, _ path: String, query: [String: String?], body: (some Encodable)?, authorized: Bool) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body, !(body is EmptyBody) {
            req.httpBody = try Self.encoder.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func validate(_ response: URLResponse, data: Data, authorized: Bool) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.transport(code: -1) }
        guard (200..<300).contains(http.statusCode) else {
            let detail = Self.detail(from: data)
            if http.statusCode == 401 && authorized && tokenProvider() != nil {
                onUnauthorized()
                throw APIError.unauthorized
            }
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default:
            return .transport(code: error.errorCode == 0 ? 503 : abs(error.errorCode))
        }
    }

    /// Extracts `detail` (string) or 429 `error`; validation arrays become their first `msg`.
    static func detail(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let s = obj["detail"] as? String { return s }
        if let arr = obj["detail"] as? [[String: Any]], let msg = arr.first?["msg"] as? String { return msg }
        return obj["error"] as? String
    }
}

/// The API serializes Decimals as JSON strings ("36.36"). Convert those to JSON
/// numbers (preserving precision) for the money keys so `Decimal` decodes directly.
enum DecimalNormalizer {
    static let moneyKeys: Set<String> = ["total_amount", "vat_total", "amount"]
    static let moneyMapKeys: Set<String> = ["vat_by_rate", "payment_method_totals", "category_totals"]

    static func normalize(_ data: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return data }
        let fixed = walk(obj, key: nil)
        return (try? JSONSerialization.data(withJSONObject: fixed, options: [.fragmentsAllowed])) ?? data
    }

    private static func walk(_ value: Any, key: String?) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if moneyMapKeys.contains(k), let map = v as? [String: Any] {
                    out[k] = map.mapValues { number($0) ?? $0 }
                } else if moneyKeys.contains(k), let n = number(v) {
                    out[k] = n
                } else {
                    out[k] = walk(v, key: k)
                }
            }
            return out
        }
        if let arr = value as? [Any] { return arr.map { walk($0, key: key) } }
        return value
    }

    private static func number(_ v: Any) -> NSDecimalNumber? {
        guard let s = v as? String else { return nil }
        let n = NSDecimalNumber(string: s, locale: Locale(identifier: "en_US_POSIX"))
        return n == .notANumber ? nil : n
    }
}

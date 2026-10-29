import Foundation

/// Small JSON disk cache used for offline display (issue #14) and widgets.
enum SessionCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("session", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func store<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(key + ".json"), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(key + ".json")) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func modified(key: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(key + ".json").path)
        return attrs?[.modificationDate] as? Date
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static var user: User? {
        get { load(User.self, key: "user") }
        set { if let newValue { store(newValue, key: "user") } }
    }
}

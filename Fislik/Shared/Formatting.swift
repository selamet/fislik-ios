import Foundation

enum DateParsing {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let naive: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        if raw.count == 10 { return day.date(from: raw) }
        if let d = iso.date(from: raw) ?? isoNoFraction.date(from: raw) { return d }
        // Microsecond precision without timezone (treated as UTC).
        let trimmed = raw.replacingOccurrences(of: "Z", with: "")
        if let d = naive.date(from: trimmed) { return d }
        let noFraction = DateFormatter()
        noFraction.locale = Locale(identifier: "en_US_POSIX")
        noFraction.timeZone = TimeZone(identifier: "UTC")
        noFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return noFraction.date(from: String(trimmed.prefix(19)))
    }

    static func dayString(_ date: Date) -> String { day.string(from: date) }
}

/// A calendar month, serialized by the API as "YYYY-MM".
struct Period: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let month: Int

    var id: String { raw }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    init(date: Date, calendar: Calendar = .fislik) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year!, month: c.month!)
    }

    static var current: Period { Period(date: Date()) }

    var raw: String { String(format: "%04d-%02d", year, month) }

    func adding(_ months: Int) -> Period {
        let index = year * 12 + (month - 1) + months
        return Period(year: index / 12, month: index % 12 + 1)
    }

    var previous: Period { adding(-1) }
    var next: Period { adding(1) }

    static func < (a: Period, b: Period) -> Bool { (a.year, a.month) < (b.year, b.month) }

    /// "Ekim"
    var monthName: String { TR.months[month - 1] }
    /// "Ekim 2026"
    var title: String { "\(monthName) \(year)" }
    /// "EKİM 2026"
    var upperTitle: String { title.uppercased(with: TR.locale) }

    func contains(_ date: Date) -> Bool { Period(date: date) == self }

    /// First day of the next month, e.g. "1 Kasım".
    var renewalLabel: String { "1 \(next.monthName)" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let p = Period(raw) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad period") }
        self = p
    }
}

extension Calendar {
    static var fislik: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = TR.locale
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }
}

/// Turkish formatting helpers matching the design copy.
enum TR {
    static let locale = Locale(identifier: "tr_TR")
    static let months = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    static let shortMonths = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
    static let weekdays = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    private static let wholeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return f
    }()

    /// "₺1.482,35"
    static func money(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return "₺" + plain(value)
    }

    /// "1.482,35"
    static func plain(_ value: Decimal) -> String {
        moneyFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// "₺6.345" (no decimals, used in compact tiles)
    static func moneyWhole(_ value: Decimal) -> String {
        "₺" + (wholeFormatter.string(from: value as NSDecimalNumber) ?? "\(value)")
    }

    /// Parses "1.482,35" / "1482.35" / "₺1.482,35".
    static func parseMoney(_ text: String) -> Decimal? {
        var s = text.replacingOccurrences(of: "₺", with: "").replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func comps(_ date: Date) -> DateComponents {
        Calendar.fislik.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    /// "24 Eki"
    static func shortDay(_ date: Date) -> String {
        let c = comps(date)
        return "\(c.day!) \(shortMonths[c.month! - 1])"
    }

    /// "24 Ekim 2026"
    static func longDay(_ date: Date) -> String {
        let c = comps(date)
        return "\(c.day!) \(months[c.month! - 1]) \(c.year!)"
    }

    /// "2 Ekim"
    static func dayMonth(_ date: Date) -> String {
        let c = comps(date)
        return "\(c.day!) \(months[c.month! - 1])"
    }

    /// "22.10.2026"
    static func dotted(_ date: Date) -> String {
        let c = comps(date)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }

    /// "14:30"
    static func time(_ date: Date) -> String {
        let c = comps(date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// "24 Ekim 2026, 14:30"
    static func longDateTime(_ date: Date) -> String { "\(longDay(date)), \(time(date))" }

    /// "22 Eki 14:03"
    static func shortDateTime(_ date: Date) -> String { "\(shortDay(date)) \(time(date))" }

    /// "Salı 27 Ekim"
    static func weekdayDay(_ date: Date) -> String {
        let c = comps(date)
        return "\(weekdays[c.weekday! - 1]) \(c.day!) \(months[c.month! - 1])"
    }

    static func upper(_ s: String) -> String { s.uppercased(with: locale) }
}

extension String {
    /// "Ayşe Yıldırım" → "AY"
    var initials: String {
        let parts = split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased(with: TR.locale)
    }

    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var isValidEmail: Bool {
        range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    /// File-name friendly slug: "Ayşe Yıldırım" → "ayse-yildirim"
    var slug: String {
        let map: [Character: String] = ["ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "İ": "i"]
        let lowered = lowercased(with: TR.locale)
        var out = ""
        for ch in lowered {
            if let r = map[ch] { out += r } else if ch.isLetter || ch.isNumber { out.append(ch) } else { out += "-" }
        }
        return out.split(separator: "-").joined(separator: "-")
    }
}

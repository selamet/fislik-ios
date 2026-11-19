import Foundation

/// A manual expense (`/expenses`): spending without a receipt.
struct Expense: Codable, Equatable, Identifiable {
    let id: String
    let period: String
    /// "YYYY-MM-DD": a calendar day, kept as text so no time zone can shift it.
    let expenseDate: String
    let amount: Decimal
    let vatAmount: Decimal?
    let category: String
    let description: String
    let createdByName: String?
    /// Generated from a recurring rule; absent on older APIs.
    var recurring: Bool?

    var dateLabel: String { ExpenseDay.label(expenseDate) }
    var isRecurring: Bool { recurring == true }
}

/// Body of `POST /expenses` and `PATCH /expenses/{id}`. VAT is always sent
/// (null clears it on an edit).
struct ExpenseBody: Encodable, Equatable {
    var expenseDate: String
    var amount: Decimal
    var vatAmount: Decimal?
    var category: String
    var description: String

    enum CodingKeys: String, CodingKey { case expenseDate, amount, vatAmount, category, description }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(expenseDate, forKey: .expenseDate)
        try c.encode(amount, forKey: .amount)
        try c.encode(vatAmount, forKey: .vatAmount)
        try c.encode(category, forKey: .category)
        try c.encode(description, forKey: .description)
    }
}

/// Calendar days as "YYYY-MM-DD", read and written in the device calendar.
enum ExpenseDay {
    static func string(_ date: Date, calendar: Calendar = .fislik) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(_ raw: String, calendar: Calendar = .fislik) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "5 Ekim 2026"
    static func label(_ raw: String) -> String {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return raw }
        return "\(parts[2]) \(TR.months[parts[1] - 1]) \(parts[0])"
    }

    /// Today in `period` when it is the current month, else that month's first day.
    static func defaultDate(for period: Period, now: Date = Date(), calendar: Calendar = .fislik) -> Date {
        if Period(date: now, calendar: calendar) == period { return now }
        return calendar.date(from: DateComponents(year: period.year, month: period.month, day: 1, hour: 12)) ?? now
    }
}

/// What the expense form holds while it is being edited.
struct ExpenseDraft: Equatable {
    var description = ""
    var amount = ""
    var vat = ""
    var category = "kira"
    var date = Date()

    init(period: Period, now: Date = Date()) {
        date = ExpenseDay.defaultDate(for: period, now: now)
    }

    init(_ expense: Expense) {
        description = expense.description
        amount = TR.plain(expense.amount)
        vat = expense.vatAmount.map(TR.plain) ?? ""
        category = expense.category
        date = ExpenseDay.date(expense.expenseDate) ?? Date()
    }

    struct Errors: Error, Equatable {
        var description: String?
        var amount: String?
        var vat: String?
        var isEmpty: Bool { description == nil && amount == nil && vat == nil }
    }

    /// The request body, or the field errors the user has to fix.
    func validated() -> Result<ExpenseBody, Errors> {
        var errors = Errors()
        let text = description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty { errors.description = "Kısa bir açıklama yaz." }
        let total = Money.parse(amount)
        if total == nil || total! <= 0 { errors.amount = "Sıfırdan büyük bir tutar gir (ör. 1.250,50)." }
        var tax: Decimal?
        if !vat.trimmingCharacters(in: .whitespaces).isEmpty {
            tax = Money.parse(vat)
            if tax == nil { errors.vat = "KDV tutarı geçersiz." }
            else if let tax, let total, tax > total { errors.vat = "KDV tutardan büyük olamaz." }
        }
        guard errors.isEmpty, let total else { return .failure(errors) }
        return .success(ExpenseBody(expenseDate: ExpenseDay.string(date), amount: total, vatAmount: tax,
                                    category: category, description: text))
    }
}

/// Turkish amount input: "15.000" is fifteen thousand, "1.250,50" and
/// "1250.5" also work; more than two decimals or anything else is refused.
enum Money {
    static func parse(_ raw: String) -> Decimal? {
        var s = raw.replacingOccurrences(of: "₺", with: "").replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if s.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            s = s.replacingOccurrences(of: ".", with: "")
        } else if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard s.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }
}

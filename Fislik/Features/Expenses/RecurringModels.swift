import Foundation

/// A recurring expense rule (`/expenses/recurring`).
struct RecurringExpense: Codable, Equatable, Identifiable {
    let id: String
    let description: String
    let amount: Decimal
    let vatAmount: Decimal?
    let category: String
    let dayOfMonth: Int
    /// Last "YYYY-MM" it generates for; nil = until paused or deleted.
    let endPeriod: String?
    let active: Bool
    let lastGeneratedPeriod: String?
    /// False while paused or while the plan does not include recurring expenses.
    let generating: Bool

    /// "Her ayın 5. günü" / "Her ayın 31. günü (kısa aylarda son gün) · Mart 2027 sonuna kadar"
    var schedule: String {
        let day = dayOfMonth >= 29 ? "\(dayOfMonth). günü (kısa aylarda son gün)" : "\(dayOfMonth). günü"
        let until = endPeriod.flatMap(Period.init).map { " · \($0.title) sonuna kadar" } ?? ""
        return "Her ayın \(day)\(until)"
    }

    /// Why the rule is not generating, if it is not.
    func note(paid: Bool) -> String? {
        if !active { return "Duraklatıldı" }
        if !paid { return "Ücretsiz planda çalışmaz" }
        return nil
    }
}

/// Body of `POST` / `PATCH /expenses/recurring`. VAT and the last month are
/// always sent, so an edit can clear them.
struct RecurringBody: Encodable, Equatable {
    var description: String
    var amount: Decimal
    var vatAmount: Decimal?
    var category: String
    var dayOfMonth: Int
    var endPeriod: String?

    enum CodingKeys: String, CodingKey { case description, amount, vatAmount, category, dayOfMonth, endPeriod }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encode(vatAmount, forKey: .vatAmount)
        try c.encode(category, forKey: .category)
        try c.encode(dayOfMonth, forKey: .dayOfMonth)
        try c.encode(endPeriod, forKey: .endPeriod)
    }
}

struct RecurringActiveBody: Encodable { let active: Bool }

struct RecurringDraft: Equatable {
    var description = ""
    var amount = ""
    var vat = ""
    var category = "kira"
    var day = 1
    var endPeriod: Period?

    init() {}

    init(_ rule: RecurringExpense) {
        description = rule.description
        amount = TR.plain(rule.amount)
        vat = rule.vatAmount.map(TR.plain) ?? ""
        category = rule.category
        day = rule.dayOfMonth
        endPeriod = rule.endPeriod.flatMap(Period.init)
    }

    /// Choices for the last month: this month and the next two years.
    static func endChoices(from start: Period = .current) -> [Period] {
        (0..<24).map { start.adding($0) }
    }

    func validated() -> Result<RecurringBody, ExpenseDraft.Errors> {
        var errors = ExpenseDraft.Errors()
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
        return .success(RecurringBody(description: text, amount: total, vatAmount: tax, category: category,
                                      dayOfMonth: min(max(day, 1), 31), endPeriod: endPeriod?.raw))
    }
}

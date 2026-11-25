import XCTest
@testable import Fislik

final class FormattingTests: XCTestCase {
    func testMoney() {
        XCTAssertEqual(TR.money(Decimal(string: "1482.35")), "₺1.482,35")
        XCTAssertEqual(TR.money(Decimal(string: "236.7")), "₺236,70")
        XCTAssertEqual(TR.money(nil), "—")
        XCTAssertEqual(TR.moneyWhole(Decimal(string: "6345.25")!), "₺6.345")
    }

    func testParseMoney() {
        XCTAssertEqual(TR.parseMoney("1.482,35"), Decimal(string: "1482.35"))
        XCTAssertEqual(TR.parseMoney("₺899,90"), Decimal(string: "899.9"))
        XCTAssertEqual(TR.parseMoney("12.5"), Decimal(string: "12.5"))
        XCTAssertNil(TR.parseMoney(""))
    }

    func testPeriodMath() {
        let p = Period("2026-10")!
        XCTAssertEqual(p.title, "Ekim 2026")
        XCTAssertEqual(p.upperTitle, "EKİM 2026")
        XCTAssertEqual(p.next.raw, "2026-11")
        XCTAssertEqual(Period("2026-01")!.previous.raw, "2025-12")
        XCTAssertEqual(Period("2026-12")!.next.raw, "2027-01")
        XCTAssertNil(Period("2026-13"))
        XCTAssertEqual(p.renewalLabel, "1 Kasım")
    }

    func testDates() {
        let d = DateParsing.parse("2026-10-24")!
        XCTAssertEqual(DateParsing.dayString(d), "2026-10-24")
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00.123456+00:00"))
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-10-24T14:30:00.123456"))
    }

    func testStrings() {
        XCTAssertEqual("Ayşe Yıldırım".initials, "AY")
        XCTAssertEqual("Elif Şahin".initials, "EŞ")
        XCTAssertEqual("Ayşe Yıldırım".slug, "ayse-yildirim")
        XCTAssertTrue("a@b.co".isValidEmail)
        XCTAssertFalse("ab.co".isValidEmail)
    }
}

final class DecodingTests: XCTestCase {
    func testReceiptDecodesStringDecimals() throws {
        let json = """
        {"id":"abc","period":"2026-10","created_at":"2026-10-22T14:03:00.000001Z","image_url":"https://x/y.jpg",
         "content_type":"image/jpeg","processed":false,"open_issue":null,"uploaded_by":null,
         "extraction":{"status":"done","merchant_name":"Trendyol","merchant_legal_name":null,"receipt_date":"2026-10-22",
          "total_amount":"899.90","vat_total":"149.98","vat_breakdown":[{"rate":20,"amount":"149.98"}],"doc_type":"fatura",
          "merchant_tax_id":null,"merchant_tax_id_type":null,"merchant_tax_office":null,"receipt_number":"123",
          "payment_method":"kredi_karti","expense_category":"ofis","edited":false}}
        """
        let r = try APIClient.decoder.decode(Receipt.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertEqual(r.extraction?.totalAmount, Decimal(string: "899.90"))
        XCTAssertEqual(r.extraction?.vatBreakdown.first?.amount, Decimal(string: "149.98"))
        XCTAssertEqual(r.extraction?.receiptNumber, "123")
        XCTAssertEqual(r.extraction?.paymentMethod, .krediKarti)
    }

    func testSummaryMaps() throws {
        let json = #"{"receipt_count":8,"analyzed_count":8,"total_amount":"6345.25","vat_total":"971.85","vat_by_rate":{"20":"821.27","10":"150.58"},"payment_method_totals":{},"category_totals":{"market":"10.00"}}"#
        let s = try APIClient.decoder.decode(MonthSummary.self, from: DecimalNormalizer.normalize(Data(json.utf8)))
        XCTAssertEqual(s.vatByRate["20"], Decimal(string: "821.27"))
        XCTAssertEqual(s.categoryTotals["market"], 10)
    }

    func testErrorDetail() {
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":"Bu ay zaten gönderildi"}"#.utf8)), "Bu ay zaten gönderildi")
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":[{"msg":"bad"}]}"#.utf8)), "bad")
        XCTAssertEqual(APIClient.detail(from: Data(#"{"error":"Rate limit"}"#.utf8)), "Rate limit")
        XCTAssertEqual(APIError.server(status: 409, detail: "Bu ay zaten gönderildi").message, "Bu ay zaten gönderildi")
        XCTAssertEqual(APIError.server(status: 404, detail: "Receipt not found").message, "Kayıt bulunamadı.")
    }

    func testPatchEncodingOmitsAndClears() throws {
        var patch = ExtractionPatch()
        patch.merchantName = .some("Migros")
        patch.merchantTaxId = .some(nil)
        let data = try APIClient.encoder.encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["merchant_name"] as? String, "Migros")
        XCTAssertTrue(obj["merchant_tax_id"] is NSNull)
        XCTAssertNil(obj["vat_total"])
    }
}

@MainActor
final class DeepLinkTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/davet/abc")!), .invite(token: "abc"))
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/sifre-sifirla/t1")!), .passwordReset(token: "t1"))
        XCTAssertEqual(AppModel.parse(URL(string: "fislik://kamera")!), .camera)
        XCTAssertEqual(AppModel.parse(URL(string: "fislik://fis/r1?period=2026-10")!), .receipt(id: "r1", period: Period("2026-10")))
    }
}

final class QueryTests: XCTestCase {
    private func receipt(_ merchant: String, total: String, processed: Bool = false, category: ExpenseCategory = .market) -> Receipt {
        Receipt(id: UUID().uuidString, period: "2026-10", createdAt: Date(), imageUrl: nil, contentType: "image/jpeg", processed: processed, openIssue: nil,
                extraction: Extraction(status: .done, merchantName: merchant, receiptDate: DateParsing.parse("2026-10-20"), totalAmount: Decimal(string: total), vatTotal: 0, vatBreakdown: [], docType: .fis, expenseCategory: category, edited: false),
                uploadedBy: nil)
    }

    func testTextAndFilters() {
        let p = Period("2026-10")!
        var q = ReceiptQuery()
        q.text = "mig"
        XCTAssertTrue(q.matches(receipt("Migros", total: "10"), period: p, now: p))
        XCTAssertFalse(q.matches(receipt("Shell", total: "10"), period: p, now: p))
        q.text = ""
        q.status = .processed
        XCTAssertFalse(q.matches(receipt("Migros", total: "10"), period: p, now: p))
        q.status = .all
        q.minAmount = "100"
        XCTAssertFalse(q.matches(receipt("Migros", total: "99,99"), period: p, now: p))
        q.minAmount = ""
        q.range = .thisMonth
        XCTAssertFalse(q.matches(receipt("Migros", total: "1"), period: p.previous, now: p))
    }

    func testDuplicatesAndWrongMonth() {
        let a = receipt("Getir", total: "164.50"), b = receipt("Getir", total: "164.50"), c = receipt("Getir", total: "1")
        XCTAssertEqual([a, b, c].duplicateIds, [a.id, b.id])
        var moved = a
        moved.period = "2026-11"
        XCTAssertTrue(moved.isWrongMonth)
        XCTAssertEqual(moved.wrongMonthTarget, Period("2026-10"))
    }
}

final class DisplayCaseTests: XCTestCase {
    func testDisplayCased() {
        XCTAssertEqual("ABDULLAH AKLAN UNLU MAMÜLLER".displayCased, "Abdullah Aklan Unlu Mamüller")
        XCTAssertEqual("KASAP HASAN".displayCased, "Kasap Hasan")
        XCTAssertEqual("İSTANBUL ŞUBESİ".displayCased, "İstanbul Şubesi")
        XCTAssertEqual("A101".displayCased, "A101")
        XCTAssertEqual("BİM".displayCased, "BİM")
        XCTAssertEqual("Türk Telekom".displayCased, "Türk Telekom")
        XCTAssertEqual("SHELL TURCAS".displayCased, "Shell Turcas")
    }
}

final class CompanyTenantTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CompanyStore.activeKey)
        super.tearDown()
    }

    private func request(_ client: APIClient) throws -> URLRequest {
        try client.makeRequest(.get, "/receipts", query: [:], body: EmptyBody?.none, authorized: true)
    }

    func testActiveCompanyIsSentAsHeader() throws {
        let client = APIClient(baseURL: URL(string: "https://example.test")!)
        XCTAssertNil(try request(client).value(forHTTPHeaderField: APIClient.companyHeader))
        client.companyIdProvider = { "co-active" }
        XCTAssertEqual(try request(client).value(forHTTPHeaderField: APIClient.companyHeader), "co-active")
    }

    func testPinnedCompanyOverridesActive() throws {
        let client = APIClient(baseURL: URL(string: "https://example.test")!)
        client.companyIdProvider = { "co-active" }
        let pinned = try APIClient.$pinnedCompanyId.withValue("co-pinned") { try request(client) }
        XCTAssertEqual(pinned.value(forHTTPHeaderField: APIClient.companyHeader), "co-pinned")
        let unpinned = try APIClient.$pinnedCompanyId.withValue(nil) { try request(client) }
        XCTAssertEqual(unpinned.value(forHTTPHeaderField: APIClient.companyHeader), "co-active")
    }

    func testUnauthorizedRequestsCarryNoCompany() throws {
        let client = APIClient(baseURL: URL(string: "https://example.test")!)
        client.companyIdProvider = { "co-active" }
        let req = try client.makeRequest(.post, "/auth/login", query: [:], body: EmptyBody?.none, authorized: false)
        XCTAssertNil(req.value(forHTTPHeaderField: APIClient.companyHeader))
    }

    func testMembershipDecodingAndCaption() throws {
        let json = #"[{"id":"c1","name":"Selamet Samli","role":"owner","member_count":3},{"id":"c2","name":"Ekin Kafe","role":"uploader"}]"#
        let list = try APIClient.decoder.decode([CompanyMembership].self, from: Data(json.utf8))
        XCTAssertEqual(list[0].caption, "Sahip · 3 üye")
        XCTAssertEqual(list[0].initials, "SS")
        XCTAssertEqual(list[1].caption, "Yükleyici")
        XCTAssertFalse(list[1].role.isManager)
    }

    func testQueuedItemsFromOlderBuildsDecodeWithoutCompany() throws {
        let item = UploadItem(id: "u1", filename: "a.jpg", period: Period("2026-11")!, contentType: "image/jpeg", needsCompression: false)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object.removeValue(forKey: "companyId")
        let legacy = try JSONDecoder().decode(UploadItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.companyId)

        var pinned = item
        pinned.companyId = "co-1"
        let roundTrip = try JSONDecoder().decode(UploadItem.self, from: JSONEncoder().encode(pinned))
        XCTAssertEqual(roundTrip.companyId, "co-1")
    }
}

final class MemberInviteTests: XCTestCase {
    @MainActor
    func testParsesMemberInviteLinks() {
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/uye-davet/tok-1")!), .memberInvite(token: "tok-1"))
        XCTAssertEqual(AppModel.parse(URL(string: "fislik://uye-davet/tok-2")!), .memberInvite(token: "tok-2"))
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/davet/g-1")!), .invite(token: "g-1"))
    }

    @MainActor
    func testMemberInvitePushOpensTheInvite() {
        XCTAssertEqual(AppModel.link(forNotification: "member_invite", payload: ["membership_id": "m-7"]), .memberInviteId("m-7"))
        XCTAssertEqual(AppModel.link(forNotification: "member_invite", payload: [:]), .notifications)
    }

    private func member(_ role: MemberRole, pending: Bool = false, me: Bool = false) -> CompanyMember {
        CompanyMember(id: UUID().uuidString, userId: pending ? nil : "u", fullName: pending ? nil : "Ayşe Yılmaz",
                      email: "a@ornek.com", role: role, status: pending ? .pending : .active, isMe: me,
                      receiptsThisMonth: 0, joinedAt: nil, invitedAt: Date())
    }

    func testManagementRulesMirrorTheAPI() {
        XCTAssertFalse(member(.owner).manageable(by: .owner))
        XCTAssertFalse(member(.admin, me: true).manageable(by: .owner))
        XCTAssertTrue(member(.admin).manageable(by: .owner))
        XCTAssertFalse(member(.admin).manageable(by: .admin))
        XCTAssertTrue(member(.uploader).manageable(by: .admin))
        XCTAssertTrue(member(.admin, pending: true).manageable(by: .admin))
        XCTAssertFalse(member(.uploader).manageable(by: .uploader))
    }

    func testDecodesMembersAndInvites() throws {
        let members = #"[{"id":"m4","user_id":null,"full_name":null,"email":"deniz@ornek.com","role":"uploader","status":"pending","is_me":false,"receipts_this_month":0,"joined_at":null,"invited_at":"2026-11-14T10:00:00Z"}]"#
        let decoded = try APIClient.decoder.decode([CompanyMember].self, from: Data(members.utf8))
        XCTAssertTrue(decoded[0].isPending)
        XCTAssertEqual(decoded[0].displayName, "deniz@ornek.com")

        let invites = #"[{"id":"i1","company_id":"c1","company_name":"Selamet Samli","role":"admin","inviter_name":null,"created_at":"2026-11-14T10:00:00Z"}]"#
        XCTAssertEqual(try APIClient.decoder.decode([MemberInvite].self, from: Data(invites.utf8))[0].role, .admin)

        let info = #"{"company_name":"Selamet Samli","role":"uploader","inviter_name":"Selamet Samli","email":"d@o.com","account_exists":true}"#
        XCTAssertTrue(try APIClient.decoder.decode(MemberInviteInfo.self, from: Data(info.utf8)).accountExists)
    }
}

final class WidgetCompanyTests: XCTestCase {
    func testOlderSnapshotsDecodeWithoutCompany() throws {
        var data = WidgetData.placeholder
        data.companyName = nil
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        object.removeValue(forKey: "companyName")
        let legacy = try JSONDecoder().decode(WidgetData.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.companyName)
        XCTAssertEqual(legacy.headerLabel, TR.upper(Period.current.monthName))
    }

    func testHeaderNamesTheCompany() {
        var data = WidgetData.placeholder
        data.companyName = "Ekin Kafe"
        XCTAssertEqual(data.headerLabel, "EKİN KAFE · \(TR.upper(Period.current.monthName))")
    }
}

final class InviteDecodingTests: XCTestCase {
    func testInviteLookupDecodes() throws {
        let json = """
        {"kind":"grant","inviter_name":"Mehmet","company_name":null,"role":"client",
         "email":"m@x.com","account_exists":true,"account_role":"client"}
        """
        let info = try APIClient.decoder.decode(InviteLookup.self, from: Data(json.utf8))
        XCTAssertEqual(info.kind, .grant)
        XCTAssertNil(info.companyName)
        XCTAssertEqual(info.accountRole, .client)
        XCTAssertEqual(info.invitedAccountRole, .client)
    }

    func testMemberInviteIsForClients() throws {
        let json = """
        {"kind":"member","inviter_name":null,"company_name":"ABC","role":"uploader",
         "email":"d@x.com","account_exists":false,"account_role":null}
        """
        let info = try APIClient.decoder.decode(InviteLookup.self, from: Data(json.utf8))
        XCTAssertEqual(info.invitedAccountRole, .client)
        XCTAssertNil(info.accountRole)
    }

    func testAuthResponseWithJoinedViaInvite() throws {
        let json = """
        {"id":"u1","email":"d@x.com","full_name":"D","role":"client","access_token":"t",
         "joined_via_invite":{"kind":"member","company_id":"c1","company_name":"ABC","role":"uploader","inviter_name":"S"}}
        """
        let auth = try APIClient.decoder.decode(AuthResponse.self, from: Data(json.utf8))
        XCTAssertEqual(auth.joinedViaInvite?.companyId, "c1")
        XCTAssertEqual(auth.joinedViaInvite?.kind, .member)
    }

    func testAuthResponseWithoutJoinedViaInvite() throws {
        let json = #"{"id":"u1","email":"d@x.com","full_name":"D","role":"client","access_token":"t"}"#
        let auth = try APIClient.decoder.decode(AuthResponse.self, from: Data(json.utf8))
        XCTAssertNil(auth.joinedViaInvite)
    }

    func testNotificationInviteStatus() throws {
        let json = """
        {"id":"n1","type":"member_invite","payload":{"membership_id":"m1"},"read":false,
         "created_at":"2026-11-25T10:00:00Z","invite_status":"pending"}
        """
        let note = try APIClient.decoder.decode(AppNotification.self, from: Data(json.utf8))
        XCTAssertEqual(note.inviteStatus, "pending")
    }
}

@MainActor
final class InviteRoutingTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "onboardingDone")
        super.tearDown()
    }

    func testParsesBothInviteLinks() {
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/uye-davet/abc")!), .memberInvite(token: "abc"))
        XCTAssertEqual(AppModel.parse(URL(string: "https://fislik.selamet.dev/davet/xyz")!), .invite(token: "xyz"))
        XCTAssertEqual(AppModel.inviteToken(of: .memberInvite(token: "abc")), "abc")
        XCTAssertEqual(AppModel.inviteToken(of: .invite(token: "xyz")), "xyz")
        XCTAssertNil(AppModel.inviteToken(of: .camera))
    }

    func testSkipsCompanySetupAfterJoiningThroughInvite() {
        XCTAssertFalse(AppModel.skipsCompanySetup(joined: nil))
        let joined = JoinedViaInvite(kind: .member, companyId: "c1", companyName: "ABC", role: "uploader", inviterName: nil)
        XCTAssertTrue(AppModel.skipsCompanySetup(joined: joined))
    }

    func testInviteLinkSkipsIntroPager() {
        let app = AppModel()
        app.phase = .onboarding
        app.handle(url: URL(string: "https://fislik.selamet.dev/uye-davet/abc")!)
        XCTAssertEqual(app.phase, .auth)
        XCTAssertEqual(app.pendingLink, .memberInvite(token: "abc"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "onboardingDone"))
    }

    func testOtherLinksKeepThePager() {
        let app = AppModel()
        app.phase = .onboarding
        app.handle(url: URL(string: "https://fislik.selamet.dev/fis/r1")!)
        XCTAssertEqual(app.phase, .onboarding)
    }
}

final class InviteCopyTests: XCTestCase {
    private func joined(_ kind: InviteKind, _ role: String, inviter: String? = nil) -> JoinedViaInvite {
        JoinedViaInvite(kind: kind, companyId: "c1", companyName: "ABC", role: role, inviterName: inviter)
    }

    func testWelcomeCopyPerRole() {
        XCTAssertEqual(InviteCopy.welcome(joined(.member, "uploader")).title, "ABC ekibine katıldın")
        XCTAssertTrue(InviteCopy.welcome(joined(.member, "uploader")).opensCamera)
        XCTAssertEqual(InviteCopy.welcome(joined(.member, "admin")).action, "Fişlere göz at")
        XCTAssertEqual(InviteCopy.welcome(joined(.grant, "accountant")).title, "ABC artık mükelleflerinde")
        XCTAssertEqual(InviteCopy.welcome(joined(.grant, "client", inviter: "Mehmet")).title, "Muhasebecin Mehmet bağlandı")
    }

    func testHeadline() {
        let info = InviteLookup(kind: .member, inviterName: "S", companyName: "ABC", role: "uploader", email: "d@x", accountExists: false, accountRole: nil)
        XCTAssertEqual(InviteCopy.headline(info), "ABC şirketine fiş yükleyici olarak davet edildin")
    }
}

final class InviteActionStateTests: XCTestCase {
    func testStateFromServerStatus() {
        XCTAssertEqual(InviteActionsRow.State(status: "pending", local: nil), .open)
        XCTAssertEqual(InviteActionsRow.State(status: "accepted", local: nil), .accepted)
        XCTAssertEqual(InviteActionsRow.State(status: "closed", local: nil), .gone)
    }

    func testLocalOutcomeWins() {
        XCTAssertEqual(InviteActionsRow.State(status: "pending", local: .declined), .declined)
        XCTAssertEqual(InviteActionsRow.State(status: "pending", local: .gone), .gone)
    }

    @MainActor
    func testInviteNotificationsCarryActions() {
        let note = AppNotification(id: "n1", type: "member_invite", payload: ["membership_id": .string("m1"), "company_name": .string("ABC")], read: false, createdAt: .now, inviteStatus: "pending")
        let content = NotificationContent(note, isAccountant: false, accountantName: nil)
        XCTAssertEqual(content.inviteAction, InviteAction(kind: .member, id: "m1", status: "pending", invitedRole: .client, inviterName: nil))
        XCTAssertNil(content.link)

        let grant = AppNotification(id: "n2", type: "grant_invite", payload: ["grant_id": .string("g1"), "role": .string("accountant")], read: false, createdAt: .now, inviteStatus: "pending")
        XCTAssertEqual(NotificationContent(grant, isAccountant: false, accountantName: nil).inviteAction?.invitedRole, .client)

        let old = AppNotification(id: "n3", type: "member_invite", payload: ["membership_id": .string("m1")], read: false, createdAt: .now)
        XCTAssertNil(NotificationContent(old, isAccountant: false, accountantName: nil).inviteAction)
    }

    @MainActor
    func testMemberInviteDeclinedText() {
        let note = AppNotification(id: "n4", type: "member_invite_declined", payload: ["email": .string("d@x.com"), "company_name": .string("ABC")], read: false, createdAt: .now)
        XCTAssertEqual(NotificationContent(note, isAccountant: false, accountantName: nil).text, "d@x.com, ABC ekip davetini reddetti")
    }
}

final class NoCompanyTests: XCTestCase {
    func testNoCompanyOnlyAfterALoadedEmptyList() {
        XCTAssertFalse(CompanyStore.showsNoCompany(loaded: false, companies: []))
        XCTAssertTrue(CompanyStore.showsNoCompany(loaded: true, companies: []))
        XCTAssertFalse(CompanyStore.showsNoCompany(loaded: true, companies: [CompanyMembership(id: "c1", name: "A", role: .owner)]))
    }
}

@MainActor
final class InviteReviewFixTests: XCTestCase {
    private let joined = JoinedViaInvite(kind: .member, companyId: "c1", companyName: "ABC", role: "uploader", inviterName: nil)

    func testWelcomeWaitsForTheSheetToClose() async {
        let app = AppModel()
        await app.didJoin(joined, deferWelcome: true)
        XCTAssertNil(app.joined)
        app.presentQueuedWelcome()
        XCTAssertEqual(app.joined, joined)
        app.presentQueuedWelcome()
        XCTAssertEqual(app.joined, joined)
    }

    func testLoginThroughInviteSkipsCompanySetup() {
        XCTAssertTrue(AppModel.skipsCompanySetup(joined: nil, inviteInProgress: true))
        XCTAssertFalse(AppModel.skipsCompanySetup(joined: nil, inviteInProgress: false))
    }

    func testLeavingTheLandingForgetsTheInvite() {
        let auth = AuthModel()
        auth.path = [.invite(token: "a")]
        auth.pendingInvite = PendingInvite(kind: .member, token: "a", role: .client)
        auth.path.append(.rolePicker(registrationToken: "r"))
        auth.syncInviteWithPath()
        XCTAssertNotNil(auth.pendingInvite)
        auth.path = []
        auth.syncInviteWithPath()
        XCTAssertNil(auth.pendingInvite)
    }
}

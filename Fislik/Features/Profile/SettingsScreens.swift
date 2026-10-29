import SwiftUI
import UserNotifications

/// Header used by pushed settings pages: "‹ Profil   Title".
struct SubpageHeader: View {
    var back = "Profil"
    let title: String

    var body: some View {
        FNavHeader(back: back, title: title)
            .padding(.leading, 8)
            .padding(.trailing, 16)
    }
}

/// 2Z — analysis credits.
struct CreditsView: View {
    @State private var store = ReceiptStore.shared
    @State private var showPlans = false

    var body: some View {
        let month = store.state(.current)
        let uploads = month.receipts.count
        let queued = month.receipts.filter(\.isQueued).count
        let used = store.credits?.used ?? 0
        let reanalyzed = max(0, used - (uploads - queued))

        VStack(spacing: 0) {
            SubpageHeader(title: "Analiz kredisi")
            ScrollView {
                VStack(spacing: 12) {
                    hero
                    HStack(spacing: 8) {
                        FStatTile(title: "YÜKLEME", value: "\(uploads)")
                        FStatTile(title: "YENİDEN", value: "\(reanalyzed)")
                        FStatTile(title: "SIRADA", value: "\(queued)", valueColor: FColor.warning)
                    }
                    FGroupedCard {
                        Text("NASIL ÇALIŞIR").fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 10)
                        RowDivider()
                        how(.zap, FColor.brand, Text("Her yüklenen fiş veya fatura ") + Text("1 kredi").fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" ile analiz edilir: tutar, KDV, VKN, tarih, kategori okunur."))
                        RowDivider()
                        how(.rotateCw, FColor.brand, Text("\"Yeniden analiz et\" de 1 kredi harcar. Elle düzeltme ücretsizdir."))
                        RowDivider()
                        how(.clock, FColor.warning, Text("Limit dolunca fişler yine yüklenir, ") + Text("sıraya alınır").fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" ve kredi yenilenince otomatik analiz edilir."))
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daha fazla kredi mi gerekiyor?").fFont(13.5, .heavy)
                            Text("Yoğun aylar için Pro plan · 250 analiz/ay").fFont(11.5, .semibold).foregroundStyle(FColor.muted)
                        }
                        Spacer()
                        FMiniButton(title: "Planları gör", color: FColor.brand) { showPlans = true }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .fCard(radius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.refreshCredits()
            await store.load(.current)
        }
        .sheet(isPresented: $showPlans) { SafariView(url: APIConfig.webURL).ignoresSafeArea() }
    }

    private var hero: some View {
        let c = store.credits
        let limit = c?.limit ?? 0
        let remaining = c?.remaining ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Period.current.upperTitle) · \(c?.unlimited == true ? "SINIRSIZ" : "STANDART PLAN")").fFont(11, .heavy, tracking: 0.4).foregroundStyle(.white.opacity(0.75))
                    if c?.unlimited == true {
                        Text("Sınırsız").fFont(34, .heavy, tracking: -1)
                    } else {
                        (Text("\(remaining) ").font(FFont.jakarta(34, .heavy)).tracking(-1) + Text("/ \(limit) kaldı").font(FFont.jakarta(16, .bold)).foregroundColor(.white.opacity(0.75)))
                    }
                }
                Spacer()
                Icon(.sparkles, size: 22)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            CreditBar(fraction: c.map { Double($0.used) / Double(max($0.limit ?? 1, 1)) } ?? 0, track: .white.opacity(0.2), fill: .white, height: 8)
            HStack {
                Text("\(c?.used ?? 0) kullanıldı")
                Spacer()
                Text(c?.unlimited == true ? "Limit yok" : "\(Period.current.renewalLabel)'da \(limit)'ye yenilenir")
            }
            .fFont(12, .semibold)
            .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(FColor.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: FColor.brand.opacity(0.5), radius: 16, y: 12)
    }

    private func how(_ icon: FIcon, _ color: Color, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 16).foregroundStyle(color).padding(.top, 2)
            text.fFont(12.5, .semibold).foregroundStyle(FColor.muted).lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

/// Persisted notification / reminder preferences (synced to the API when supported).
struct NotificationPrefs: Codable, Equatable {
    var issueOpened = true
    var receiptsProcessed = true
    var periodLocked = true
    var grantEvents = false
    var monthEndReminder = true
    var weeklyDigest = false

    static var current: NotificationPrefs {
        get { (UserDefaults.standard.data(forKey: "notificationPrefs")).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? NotificationPrefs() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "notificationPrefs") }
    }
}

/// 2AA — notification preferences, language and appearance.
struct NotificationPrefsView: View {
    @Environment(AppModel.self) private var app
    @State private var prefs = NotificationPrefs.current
    @State private var pushStatus: UNAuthorizationStatus = .notDetermined
    @State private var syncing = false
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("language") private var language = "tr"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Bildirimler")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FGroupedCard {
                        SettingsRow(icon: .bell, title: "Anlık bildirimler", subtitle: pushSubtitle) {
                            Toggle("", isOn: Binding(get: { pushStatus == .authorized }, set: { _ in togglePush() }))
                                .toggleStyle(FToggleStyle()).labelsHidden().fixedSize()
                        }
                    }
                    section(app.isAccountant ? "MÜKELLEF" : "MUHASEBECİ")
                    FGroupedCard {
                        if app.isAccountant {
                            toggle("Fiş gönderildiğinde", subtitle: "Mükellef ayın fişlerini gönderdiğinde", $prefs.receiptsProcessed)
                            RowDivider()
                            toggle("Soru yanıtlandığında", $prefs.issueOpened)
                        } else {
                            toggle("Fişim için soru sorulduğunda", subtitle: "Önerilir — hızlı yanıt ayın kapanmasını hızlandırır", $prefs.issueOpened)
                            RowDivider()
                            toggle("Fişlerim işlendiğinde", $prefs.receiptsProcessed)
                            RowDivider()
                            toggle("Ay kapatıldığında", $prefs.periodLocked)
                        }
                        RowDivider()
                        toggle("Davet kabul / red", $prefs.grantEvents)
                    }
                    section("HATIRLATMALAR")
                    FGroupedCard {
                        toggle("Ay sonu gönderim hatırlatması", subtitle: "Ayın son 3 günü, 18:00", $prefs.monthEndReminder)
                        RowDivider()
                        toggle("Haftalık özet", subtitle: "Pazartesi 09:00 · bu hafta kaç fiş, toplam", $prefs.weeklyDigest)
                    }
                    section("DİL · GÖRÜNÜM")
                    FGroupedCard {
                        SettingsRow(title: "Dil") {
                            FSegmented(options: [("tr", "Türkçe"), ("en", "English")], selection: $language, height: 34).fixedSize()
                        }
                        RowDivider()
                        SettingsRow(title: "Görünüm") {
                            FSegmented(options: Appearance.allCases.map { ($0, $0.label) }, selection: $appearance, height: 34).fixedSize()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            pushStatus = await PushManager.shared.authorizationStatus()
            if let remote = try? await API.preferences(), remote != prefs {
                syncing = true
                prefs = remote
                NotificationPrefs.current = remote
            }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { Task { pushStatus = await PushManager.shared.authorizationStatus() } }
        }
        .onChange(of: prefs) { _, new in
            NotificationPrefs.current = new
            LocalNotifier.scheduleReminders(monthEnd: new.monthEndReminder, weekly: new.weeklyDigest)
            // Values just loaded from the server don't need to be written back.
            if syncing { syncing = false; return }
            Task { try? await API.savePreferences(new) }
        }
    }

    private var pushSubtitle: String {
        switch pushStatus {
        case .authorized, .provisional, .ephemeral: "iOS izin verildi"
        case .denied: "Ayarlar'dan izin vermelisin"
        default: "Henüz izin istenmedi"
        }
    }

    private func togglePush() {
        Task {
            if pushStatus == .notDetermined {
                _ = await PushManager.shared.requestAuthorization()
                pushStatus = await PushManager.shared.authorizationStatus()
            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted).padding(.horizontal, 2)
    }

    private func toggle(_ title: String, subtitle: String? = nil, _ binding: Binding<Bool>) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: binding).toggleStyle(FToggleStyle()).labelsHidden().fixedSize()
        }
    }
}

/// Şifre değiştir.
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var again = ""
    @State private var saving = false
    @State private var error: String?
    @State private var done = false

    private var mismatch: Bool { !again.isEmpty && new != again }

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "Şifre değiştir")
            ScrollView {
                VStack(spacing: 14) {
                    FTextField(label: "Mevcut şifre", text: $current, secure: true, contentType: .password, autocapitalization: .never)
                    VStack(alignment: .leading, spacing: 6) {
                        FTextField(label: "Yeni şifre", text: $new, placeholder: "En az 8 karakter", secure: true, contentType: .newPassword, autocapitalization: .never)
                        PasswordStrengthBar(password: new)
                    }
                    FTextField(label: "Yeni şifre (tekrar)", text: $again, secure: true, error: mismatch ? "Yeni şifreler birbiriyle eşleşmiyor" : nil, contentType: .newPassword, autocapitalization: .never)
                    if done { FBanner(icon: .circleCheck, tone: .success, text: Text("Şifren güncellendi.")) }
                    AuthErrorText(error: error)
                    Button(action: save) { FButtonLabel(title: "Şifreyi güncelle", loading: saving) }
                        .buttonStyle(.fPrimary)
                        .disabled(current.isEmpty || new.count < 8 || new != again || saving)
                }
                .padding(18)
                .fCard(radius: 20)
                .padding(16)
            }
        }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func save() {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await API.changePassword(current: current, new: new)
                done = true
                current = ""; new = ""; again = ""
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch let e as APIError {
                switch e.status {
                case 400: error = "Mevcut şifre hatalı."
                case 429: error = "Çok fazla deneme. Biraz sonra tekrar dene."
                default: error = e.message
                }
            } catch {}
        }
    }
}

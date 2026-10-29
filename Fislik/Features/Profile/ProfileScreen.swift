import LocalAuthentication
import SwiftUI

/// 2Y — profile & settings.
struct ProfileScreen: View {
    /// Pushes a settings route on the current tab's stack.
    let push: (ClientRoute) -> Void

    @Environment(AppModel.self) private var app
    @State private var store = ReceiptStore.shared
    @State private var company: CompanyProfile?
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?
    @AppStorage("autoUploadAfterCapture") private var autoUpload = true
    @AppStorage("appearance") private var appearance = Appearance.system

    private var biometryAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profil").fFont(30, .heavy, tracking: -0.9).padding(.top, 44)

                    if let user = app.user {
                        Button { if !app.isAccountant { push(.company) } } label: {
                            HStack(spacing: 14) {
                                FAvatar(initials: user.initials, size: 56, radius: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.fullName).fFont(17, .heavy)
                                    Text("\(app.isAccountant ? "Muhasebeci" : "Mükellef") · \(user.email)").fFont(12.5, .semibold).foregroundStyle(FColor.muted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
                            }
                            .foregroundStyle(FColor.ink)
                            .padding(14)
                            .fCard(radius: 18)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { push(.credits) } label: { CreditsRow(credits: store.credits) }
                        .buttonStyle(.plain)

                    FGroupedCard {
                        if !app.isAccountant {
                            navRow(.building, "Firma bilgileri", subtitle: company.map { [$0.tradeName ?? $0.fullName, "VKN \($0.taxNumber)"].joined(separator: " · ") } ?? "Henüz eklenmedi") { push(.company) }
                            RowDivider()
                        }
                        navRow(.keyRound, "Şifre değiştir") { push(.changePassword) }
                        if biometryAvailable {
                            RowDivider()
                            toggleRow(.scanFace, "Face ID ile giriş", isOn: Binding(get: { app.faceIDEnabled }, set: { app.setFaceID($0) }))
                        }
                    }

                    FGroupedCard {
                        navRow(.bell, "Bildirim tercihleri", subtitle: "Soru, işlendi, ay kapandı · Anında") { push(.notificationPrefs) }
                        RowDivider()
                        toggleRow(.camera, "Çekimden sonra otomatik yükle", subtitle: "Kapalıysa önce önizleme gösterilir", isOn: $autoUpload)
                        RowDivider()
                        navRow(.sun, "Görünüm", trailing: appearance.label) { push(.notificationPrefs) }
                    }

                    if let error { FBanner(icon: .circleAlert, tone: .danger, text: Text(error)) }

                    Button { confirmLogout = true } label: { FButtonLabel(title: "Çıkış yap", icon: .logOut) }
                        .buttonStyle(.f(.dangerOutline, height: 46, fontSize: 14))

                    HStack(spacing: 14) {
                        Link("Gizlilik", destination: APIConfig.webURL.appendingPathComponent("gizlilik"))
                        Link("Koşullar", destination: APIConfig.webURL.appendingPathComponent("kosullar"))
                        Link("Destek", destination: APIConfig.webURL.appendingPathComponent("destek"))
                    }
                    .fFont(12, .bold)
                    .foregroundStyle(FColor.brand)
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 0) {
                        Button("Hesabı sil") { confirmDelete = true }.foregroundStyle(FColor.danger)
                        Text(" · Sürüm \(version) · powered by ")
                        Link("selamet.dev", destination: URL(string: "https://selamet.dev")!).foregroundStyle(FColor.faint)
                    }
                    .fFont(11.5, .semibold)
                    .foregroundStyle(FColor.faint)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }

            if confirmLogout {
                FDialog(icon: .logOut, tint: FColor.danger, title: "Çıkış yap", confirmTitle: "Çıkış yap", confirmKind: .danger, onCancel: { confirmLogout = false }, onConfirm: {
                    confirmLogout = false
                    Task { await app.signOut() }
                }) {
                    Text(UploadQueue.shared.activeCount > 0 ? "Bekleyen \(UploadQueue.shared.activeCount) yükleme iptal edilecek. Çıkış yapmak istediğine emin misin?" : "Bu cihazdan çıkış yapılacak.")
                        .dialogMessage()
                }
            }
            if confirmDelete {
                FDialog(icon: .trash, tint: FColor.danger, title: "Hesabı sil", confirmTitle: "Hesabı sil", confirmKind: .danger, busy: deleting, onCancel: { confirmDelete = false }, onConfirm: deleteAccount) {
                    (Text("Hesabın ve ") + Text("tüm fişlerin, bağlantıların, bildirimlerin").fontWeight(.heavy).foregroundColor(FColor.ink) + Text(" kalıcı olarak silinecek. Bu işlem geri alınamaz."))
                        .dialogMessage()
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmLogout || confirmDelete)
        .background(FColor.bg.ignoresSafeArea())
        .fStatusBarBackdrop()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        await store.refreshCredits()
        if !app.isAccountant { company = try? await API.company() }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            defer { deleting = false }
            do {
                try await API.deleteAccount()
                confirmDelete = false
                app.signOutLocally()
            } catch let e as APIError {
                confirmDelete = false
                error = e.message
            } catch {}
        }
    }

    private func navRow(_ icon: FIcon, _ title: String, subtitle: String? = nil, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(icon: icon, title: title, subtitle: subtitle) {
                if let trailing { Text(trailing).fFont(12.5, .semibold).foregroundStyle(FColor.muted) }
                Icon(.chevronRight, size: 16).foregroundStyle(FColor.ink.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ icon: FIcon, _ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn).toggleStyle(FToggleStyle()).labelsHidden().fixedSize()
        }
    }
}

/// Row with teal leading icon, title/subtitle and trailing accessory.
struct SettingsRow<Trailing: View>: View {
    var icon: FIcon?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon { Icon(icon, size: 18).foregroundStyle(FColor.brand) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fFont(14, .bold)
                if let subtitle { Text(subtitle).fFont(11.5, .semibold).foregroundStyle(FColor.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// "Analiz kredisi 12 / 50" row with progress.
struct CreditsRow: View {
    let credits: Credits?

    var body: some View {
        HStack(spacing: 12) {
            FIconTile(icon: .package, size: 40, iconSize: 18)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Analiz kredisi")
                    Spacer()
                    if let c = credits {
                        if c.unlimited {
                            Text("Sınırsız")
                        } else {
                            Text("\(c.used) ") + Text("/ \(c.limit ?? 0)").foregroundColor(FColor.muted).fontWeight(.semibold)
                        }
                    }
                }
                .fFont(13.5, .heavy)
                CreditBar(fraction: credits.map { c in c.unlimited ? 0 : Double(c.used) / Double(max(c.limit ?? 1, 1)) } ?? 0, track: FColor.ink.opacity(0.08), fill: credits?.exhausted == true ? FColor.warning : FColor.brand, height: 5)
                    .padding(.top, 6)
                Text("\(Period.current.renewalLabel)'da yenilenir · Standart plan").fFont(11, .semibold).foregroundStyle(FColor.muted).padding(.top, 4)
            }
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .fCard(radius: 16)
    }
}

struct CreditBar: View {
    let fraction: Double
    var track: Color
    var fill: Color
    var height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

import SwiftUI

// Temporary stand-ins; each one is replaced by its feature issue.

struct LoadErrorView: View {
    let error: APIError
    let retry: () -> Void
    var body: some View { Button("Tekrar dene", action: retry) }
}

struct CreditsView: View { var body: some View { Text("Kredi") } }
struct NotificationPrefsView: View { var body: some View { Text("Tercihler") } }
struct ChangePasswordView: View { var body: some View { Text("Şifre") } }
struct NotificationsScreen: View { var body: some View { Text("Bildirimler") } }
struct ProfileScreen: View { var body: some View { Text("Profil") } }

struct AccountantTabView: View {
    var body: some View { Text("Mükellefler").fFont(30, .heavy) }
}

enum WidgetSnapshot {
    @MainActor static func update(from store: ReceiptStore, period: Period) {}
}

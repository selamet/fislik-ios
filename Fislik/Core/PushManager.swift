import Foundation
import UserNotifications
import UIKit

/// APNs registration and notification presentation. Server delivery needs selamet/fislik-api#147.
final class PushManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PushManager()

    private(set) var deviceToken: String?
    /// Invoked on tap with the notification's `type` and string payload values.
    var onOpen: ((String, [String: String]) -> Void)?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { try? await API.registerDevice(token: token) }
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        var payload: [String: String] = [:]
        for (key, value) in (info["payload"] as? [String: Any]) ?? [:] {
            payload[key] = "\(value)"
        }
        let result = payload
        await MainActor.run { onOpen?(type, result) }
    }
}

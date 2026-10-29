import UIKit
import UserNotifications

/// Local notifications posted by the app itself (uploads finished, reminders).
@MainActor
enum LocalNotifier {
    private static var finishedInBatch = 0

    /// Batches "N fiş yüklendi" until the queue drains; only posts when the app is not active.
    static func uploadFinished(remaining: Int) {
        finishedInBatch += 1
        guard remaining == 0 else { return }
        let count = finishedInBatch
        finishedInBatch = 0
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Fişlik"
        content.body = "\(count) fiş yüklendi ve analize gönderildi · \(Period.current.title)"
        content.sound = .default
        content.userInfo = ["type": "uploads_finished"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "uploads-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    /// Month-end reminder (last 3 days of the month at 18:00) and weekly digest (Monday 09:00).
    static func scheduleReminders(monthEnd: Bool, weekly: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["month-end-1", "month-end-2", "month-end-3", "weekly"])
        if monthEnd {
            let cal = Calendar.fislik
            let now = Date()
            let range = cal.range(of: .day, in: .month, for: now) ?? 1..<31
            let last = range.upperBound - 1
            for (i, day) in [last - 2, last - 1, last].enumerated() {
                var comps = cal.dateComponents([.year, .month], from: now)
                comps.day = day
                comps.hour = 18
                guard let date = cal.date(from: comps), date > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Ay sonu yaklaşıyor"
                content.body = "\(Period.current.title) fişlerini muhasebecine göndermeyi unutma."
                content.userInfo = ["type": "month_end_reminder"]
                let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour], from: date), repeats: false)
                center.add(UNNotificationRequest(identifier: "month-end-\(i + 1)", content: content, trigger: trigger))
            }
        }
        if weekly {
            let content = UNMutableNotificationContent()
            content.title = "Haftalık özet"
            content.body = "Bu hafta yüklediğin fişlere göz at."
            content.userInfo = ["type": "weekly_digest"]
            var comps = DateComponents()
            comps.weekday = 2
            comps.hour = 9
            center.add(UNNotificationRequest(identifier: "weekly", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}

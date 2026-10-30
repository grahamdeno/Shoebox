import Foundation
import SwiftData
import UserNotifications

/// One notification a day, at the time you choose: "5 came out of the box".
/// Scheduled on the phone for the next 7 days; rescheduled every time the app opens or closes.
@MainActor
enum Notifier {
    static func ask() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        Prefs.notificationsOn = granted
        return granted
    }

    static func schedule(_ context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<8).map { "daily-\($0)" })
        guard Prefs.notificationsOn else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        let rules = TodayRules()
        let cal = Calendar.current
        let now = Date()
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                  let at = cal.date(byAdding: .minute, value: Prefs.dailyMinute, to: day), at > now else { continue }
            // What tomorrow's box would hold if nothing changes before then.
            let ids = rules.pick(all, now: at, previousDay: nil, previousIds: [], perDay: Prefs.perDay)
            let posts = rules.today(all, ids: ids, now: at)
            guard let first = posts.first else { continue }
            let content = UNMutableNotificationContent()
            content.title = posts.count == 1 ? "1 came out of the box" : "\(posts.count) came out of the box"
            content.body = posts.count == 1 ? first.headline : "\(first.headline), plus \(posts.count - 1) more."
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let req = UNNotificationRequest(identifier: "daily-\(offset)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }

    static func timeLabel(_ minute: Int) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .minute, value: minute, to: cal.startOfDay(for: Date())) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}

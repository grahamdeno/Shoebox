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
        let cal = Calendar.current
        for (offset, n) in plan(all, now: Clock.now, minute: Prefs.dailyMinute, perDay: Prefs.perDay, calendar: cal).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: n.at)
            let req = UNNotificationRequest(identifier: "daily-\(offset)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }

    /// One planned notification: when, and its words.
    struct Planned: Equatable {
        let at: Date
        let title: String
        let body: String
    }

    /// The next 7 days' notifications, if nothing changes before then (SPEC 2.9): one a day at the chosen time, naming
    /// the first post and how many more. A day with nothing coming out has none, and a time already gone today is skipped.
    static func plan(_ all: [Save], now: Date, minute: Int, perDay: Int, calendar cal: Calendar) -> [Planned] {
        let rules = TodayRules(calendar: cal)
        var out: [Planned] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                  let at = cal.date(byAdding: .minute, value: minute, to: day), at > now else { continue }
            let ids = rules.pick(all, now: at, previousDay: nil, previousIds: [], perDay: perDay)
            let posts = rules.today(all, ids: ids, now: at)
            guard let first = posts.first else { continue }
            out.append(Planned(at: at,
                               title: posts.count == 1 ? "1 came out of the box" : "\(posts.count) came out of the box",
                               body: posts.count == 1 ? first.headline : "\(first.headline), plus \(posts.count - 1) more."))
        }
        return out
    }

    static func timeLabel(_ minute: Int) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .minute, value: minute, to: cal.startOfDay(for: Clock.now)) ?? Clock.now
        return d.formatted(date: .omitted, time: .shortened)
    }
}

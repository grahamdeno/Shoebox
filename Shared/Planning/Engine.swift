import Foundation
import SwiftData
import UserNotifications
import ShoeboxCore

/// Runs after anything changes (app open, background refresh, a save from the share sheet, any verdict):
/// closes windows that ended, plans what's unplanned, recomposes the Issues and reschedules notifications.
@MainActor
enum Engine {
    static let actionDone = "DONE", actionLater = "LATER", actionDrop = "DROP", actionOpen = "OPEN"
    static let categoryIssue = "ISSUE"

    static func refresh(_ keeper: Keeper = .shared()) async {
        let events = CalendarReader.upcoming()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let canNotify = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        sweep(keeper, events: events, canNotify: canNotify)
        for s in keeper.allSaves() where s.status == .unplanned { keeper.plan(s, events: events) }
        try? keeper.context.save()
        for s in keeper.allSaves().filter({ $0.status == .planned && $0.modelPlannedAt == nil && !$0.reason.isEmpty }).prefix(5) {
            await PlannerModel.refine(s, keeper: keeper, events: events)
        }
        await schedule(keeper)
        await LiveMoments.update(keeper)
        Spotlight.index(keeper.allSaves(includeDeleted: true))
        WidgetsBridge.reload()
    }

    /// SPEC 5: a window that closed with no verdict is a pass, if it reached you. If notifications were off,
    /// it never reached you: cancelled and re-planned, not passed.
    static func sweep(_ keeper: Keeper, events: [CalendarEventInfo], canNotify: Bool) {
        let now = keeper.now()
        // SPEC 7.6: the inbox empties itself. Undated posts left 7 days go quiet; dated ones keep their steps.
        for s in keeper.allSaves() where s.inInbox {
            guard let since = s.inboxAt, now.timeIntervalSince(since) > 7 * 86_400 else { continue }
            s.inboxAt = nil
            if s.dueDate == nil {
                if let m = keeper.nextMoment(for: s) { m.state = .cancelled }
                s.status = .quiet; s.quietAt = now; s.nextMomentId = nil
                keeper.log(s, .quiet, detail: "inbox 7 days")
            }
        }
        for m in keeper.openMoments() {
            if m.start <= now && m.deliveredAt == nil && canNotify { m.deliveredAt = m.start; m.state = .delivered }
            guard m.end <= now, let save = keeper.save(id: m.saveId), save.deletedAt == nil, save.nextMomentId == m.id else {
                if m.end <= now { m.state = .cancelled }
                continue
            }
            if m.deliveredAt != nil {
                keeper.pass(save, events: events, surface: m.surfaceRaw)
            } else {
                m.state = .cancelled
                save.nextMomentId = nil
                keeper.plan(save, events: events)
            }
        }
    }

    // MARK: Notifications

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
    }

    /// Local notifications are fixed once scheduled, so everything for the next 7 days is rebuilt each time.
    static func schedule(_ keeper: Keeper) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("moment.") || $0.hasPrefix("issue.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let now = keeper.now()
        let horizon = now.addingTimeInterval(7 * 86_400)
        let cal = keeper.calendar
        let prefs = Prefs.load()
        var categories: [String: UNNotificationCategory] = [categoryIssue: issueCategory()]
        var issueDays: [Date: [(Save, Moment)]] = [:]
        var requests: [UNNotificationRequest] = []

        for m in keeper.openMoments() where m.start < horizon {
            guard m.state == .scheduled, let s = keeper.save(id: m.saveId), s.deletedAt == nil, s.nextMomentId == m.id else { continue }
            if m.surface == .issue {
                issueDays[cal.startOfDay(for: m.start), default: []].append((s, m))
                continue
            }
            guard m.start > now else { continue }
            let word = doneWord(s)
            let cat = momentCategory(done: word, later: m.laterLabel)
            categories[cat.identifier] = cat
            let c = UNMutableNotificationContent()
            c.title = s.headline
            c.body = s.reason.isEmpty ? (s.host ?? s.kind.rawValue.capitalized) : s.title
            c.categoryIdentifier = cat.identifier
            c.threadIdentifier = "moments"
            c.interruptionLevel = m.surface == .liveActivity ? .timeSensitive : .active
            c.relevanceScore = m.surface == .liveActivity ? 1 : 0.6
            c.userInfo = ["saveId": s.id.uuidString, "momentId": m.id.uuidString]
            c.sound = nil
            if let pic = keeper.picture(for: s), let a = try? attachment(pic) { c.attachments = [a] }
            requests.append(UNNotificationRequest(identifier: "moment.\(m.id.uuidString)", content: c, trigger: trigger(m.start, cal)))
        }

        // The Daily Issue: one per day with something in it. Never padded.
        for (day, items) in issueDays {
            let issueTime = DailyIssue.time(on: day, weekday: (prefs.weekdayIssue.hour, prefs.weekdayIssue.minute),
                                            weekend: (prefs.weekendIssue.hour, prefs.weekendIssue.minute), calendar: cal)
            let fire = max(issueTime, now.addingTimeInterval(5))
            guard cal.isDate(fire, inSameDayAs: day) else { continue }
            let lines = issueLines(items.map(\.0), calendar: cal)
            let comp = DailyIssue.compose(saves: lines.filter { !$0.isSchool }, school: lines.filter(\.isSchool))
            guard !comp.lines.isEmpty else { continue }
            // Overflow waits for the next Issue with room.
            for id in comp.overflow {
                if let s = keeper.save(id: id), let m = keeper.nextMoment(for: s), let next = cal.date(byAdding: .day, value: 1, to: m.start) {
                    m.start = next; m.end = cal.date(bySettingHour: 23, minute: 59, second: 0, of: next) ?? next; m.updatedAt = now
                }
            }
            let c = UNMutableNotificationContent()
            c.title = comp.cover
            c.body = comp.more ?? ""
            c.categoryIdentifier = categoryIssue
            c.threadIdentifier = "issue"
            c.interruptionLevel = .passive
            c.userInfo = ["issue": comp.lines.flatMap { line in [line.saveId] + (sameDate[line.saveId] ?? []) }.map(\.uuidString)]
            if let first = comp.lines.first, let s = keeper.save(id: first.saveId), let pic = keeper.picture(for: s), let a = try? attachment(pic) {
                c.attachments = [a]
            }
            requests.append(UNNotificationRequest(identifier: "issue.\(Int(day.timeIntervalSince1970))", content: c, trigger: trigger(fire, cal)))
        }
        try? keeper.context.save()

        center.setNotificationCategories(Set(categories.values))
        // iOS keeps 64 pending; the soonest matter most.
        for r in requests.sorted(by: { fireDate($0) < fireDate($1) }).prefix(60) { try? await center.add(r) }
    }

    /// Posts with the same date share one line: "Nov 3: no school, report cards" (SPEC 7.6).
    /// The other saves on a shared line are kept here so the opened Issue can show and answer each.
    static var sameDate: [UUID: [UUID]] = [:]

    static func issueLines(_ saves: [Save], calendar: Calendar) -> [DailyIssue.Line] {
        var out: [DailyIssue.Line] = []
        var byDay: [Date: [Save]] = [:]
        for s in saves {
            if s.isSchool, let d = s.dueDate { byDay[calendar.startOfDay(for: d), default: []].append(s) }
            else { out.append(DailyIssue.Line(saveId: s.id, reason: s.reason, title: s.title, isSchool: s.isSchool)) }
        }
        for (day, group) in byDay.sorted(by: { $0.key < $1.key }) {
            guard let first = group.first else { continue }
            if group.count == 1 {
                out.append(DailyIssue.Line(saveId: first.id, reason: first.reason, title: first.title, isSchool: true))
                continue
            }
            let names = group.map { $0.headline.prefix(1).lowercased() + $0.headline.dropFirst() }
            let text = day.formatted(.dateTime.month(.abbreviated).day()) + ": " + names.joined(separator: ", ")
            sameDate[first.id] = group.dropFirst().map(\.id)
            out.append(DailyIssue.Line(saveId: first.id, reason: String(text.prefix(140)), title: first.title, isSchool: true))
        }
        return out
    }

    /// The concrete Later on a moment maps back to the choice it stands for.
    static func laterChoice(for label: String?) -> LaterChoice {
        switch (label ?? "").lowercased() {
        case "tonight": return .tonight
        case "tomorrow", "tomorrow morning": return .tomorrowMorning
        case "this weekend", "saturday", "sunday", "weekend": return .thisWeekend
        case "next week", "monday": return .nextWeek
        default: return .youChoose
        }
    }

    static func doneWord(_ s: Save) -> String {
        VerdictWords.doneWord(kind: s.kind, intent: s.intent, reason: s.reason, isBook: s.isBook, school: schoolKind(s))
    }

    static func schoolKind(_ s: Save) -> SchoolPostKind? {
        guard let j = s.schoolJSON?.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: j)) as? [String: Any],
              let k = o["kind"] as? String else { return nil }
        return SchoolPostKind(rawValue: k)
    }

    private static func momentCategory(done: String, later: String) -> UNNotificationCategory {
        let id = "MOMENT|\(done)|\(later)"
        let actions = [
            UNNotificationAction(identifier: actionDone, title: done, options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark")),
            UNNotificationAction(identifier: actionLater, title: later, options: [], icon: UNNotificationActionIcon(systemImageName: "clock")),
            UNNotificationAction(identifier: actionDrop, title: "Drop", options: [.destructive]),
        ]
        return UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [.customDismissAction])
    }

    private static func issueCategory() -> UNNotificationCategory {
        UNNotificationCategory(identifier: categoryIssue, actions: [], intentIdentifiers: [], options: [.customDismissAction])
    }

    private static func trigger(_ date: Date, _ cal: Calendar) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
    }

    private static func fireDate(_ r: UNNotificationRequest) -> Date {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }

    /// Notification attachments are moved by the system, so a copy is handed over.
    private static func attachment(_ url: URL) throws -> UNNotificationAttachment {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + url.pathExtension)
        try FileManager.default.copyItem(at: url, to: tmp)
        return try UNNotificationAttachment(identifier: url.lastPathComponent, url: tmp)
    }

    // MARK: Answers from a notification (no unlock needed: actions don't open the app)

    static func handle(action: String, userInfo: [AnyHashable: Any], keeper: Keeper = .shared()) async {
        let events = CalendarReader.upcoming()
        if let ids = userInfo["issue"] as? [String] {
            // Dismissing the whole Issue passes every line still open.
            if action == UNNotificationDismissActionIdentifier {
                for id in ids.compactMap(UUID.init(uuidString:)) { if let s = keeper.save(id: id), s.status == .planned { keeper.pass(s, events: events, surface: "issue") } }
            }
            await refresh(keeper)
            return
        }
        guard let sid = (userInfo["saveId"] as? String).flatMap(UUID.init(uuidString:)), let s = keeper.save(id: sid) else { return }
        switch action {
        case actionDone: keeper.done(s, surface: "lockScreen")
        case actionDrop: keeper.drop(s, surface: "lockScreen")
        case actionLater: keeper.later(s, laterChoice(for: keeper.nextMoment(for: s)?.laterLabel), events: events, surface: "lockScreen")
        case UNNotificationDismissActionIdentifier: keeper.pass(s, events: events, surface: "lockScreen")
        default: keeper.opened(s, surface: "notification")
        }
        await refresh(keeper)
    }
}

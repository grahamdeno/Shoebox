import Foundation
import EventKit
import ShoeboxCore

/// Reads the calendar on the phone (SPEC 9: calendar data never leaves it).
enum CalendarReader {
    static var allowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Events from now through the next 60 days, as the planner sees them.
    static func upcoming(days: Int = 60, now: Date = .now) -> [CalendarEventInfo] {
        guard allowed else { return [] }
        let store = EKEventStore()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let pred = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now), end: end, calendars: nil)
        return store.events(matching: pred).compactMap { e in
            guard let start = e.startDate, let finish = e.endDate else { return nil }
            return CalendarEventInfo(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "", start: start, end: finish, isAllDay: e.isAllDay)
        }
    }

    static func event(id: String) -> CalendarEventInfo? {
        guard allowed, let e = EKEventStore().event(withIdentifier: id), let s = e.startDate, let f = e.endDate else { return nil }
        return CalendarEventInfo(id: id, title: e.title ?? "", start: s, end: f, isAllDay: e.isAllDay)
    }
}

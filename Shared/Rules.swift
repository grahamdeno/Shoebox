import Foundation

/// What is on Today right now. Pure logic, no UI, so it can be tested.
struct TodayRules {
    var calendar: Calendar = .current

    func isOnToday(_ s: Save, now: Date) -> Bool {
        if s.deletedAt != nil { return false }
        if let seen = s.seenOn, calendar.isDate(seen, inSameDayAs: now) { return false }
        switch s.status {
        case .kept: return false
        case .today: return true
        case .away:
            guard let due = s.returnDate else { return false }
            return due <= now
        }
    }

    /// Returning and dated saves first, then the rest, oldest first.
    func queue(_ all: [Save], now: Date) -> [Save] {
        let due = all.filter { isOnToday($0, now: now) }
        let returning = due.filter { $0.returnDate != nil }.sorted { ($0.returnDate ?? now) < ($1.returnDate ?? now) }
        let fresh = due.filter { $0.returnDate == nil }.sorted { $0.createdAt < $1.createdAt }
        return returning + fresh
    }

    /// The key for a day's pick, like "2026-10-30".
    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today's pick. Everything coming back (put away until now, dated steps) always comes out.
    /// The pile fills the rest up to `perDay`: posts passed before come first (back tomorrow means
    /// back tomorrow), then the oldest never seen. The pick is kept for the day so the count only goes down.
    func pick(_ all: [Save], now: Date, previousDay: String?, previousIds: [String], perDay: Int) -> [String] {
        let due = all.filter { isOnToday($0, now: now) }
        let returning = due.filter { $0.status == .away }.sorted { ($0.returnDate ?? now) < ($1.returnDate ?? now) }
        if previousDay == dayKey(now) {
            var ids = previousIds
            for s in returning where !ids.contains(s.id.uuidString) { ids.append(s.id.uuidString) }
            return ids
        }
        let pile = due.filter { $0.status == .today }.sorted { a, b in
            switch (a.seenOn, b.seenOn) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.createdAt < b.createdAt
            }
        }
        let room = max(0, perDay - returning.count)
        return returning.map(\.id.uuidString) + pile.prefix(room).map(\.id.uuidString)
    }

    /// The posts on Today right now, in pick order.
    func today(_ all: [Save], ids: [String], now: Date) -> [Save] {
        let byId = Dictionary(all.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }.filter { isOnToday($0, now: now) }
    }

    func away(_ all: [Save], now: Date) -> [Save] {
        all.filter { $0.deletedAt == nil && $0.status == .away && !isOnToday($0, now: now) }
            .sorted { ($0.returnDate ?? .distantFuture) < ($1.returnDate ?? .distantFuture) }
    }

    func kept(_ all: [Save]) -> [Save] {
        all.filter { $0.deletedAt == nil && $0.status == .kept }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// What each action does to a save.
struct SaveActions {
    var calendar: Calendar = .current

    /// Reminder days for a dated save: 5 days before, 1 day before, on the day, at 8 AM.
    func reminders(for eventDate: Date) -> [Date] {
        let day = calendar.startOfDay(for: eventDate)
        return [-5, -1, 0].compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
            return calendar.date(byAdding: .hour, value: 8, to: d)
        }
    }

    /// Swipe up. Seen once, gone until tomorrow. Dated saves move to their next reminder.
    func pass(_ s: Save, now: Date) {
        s.seenOn = now
        if let event = s.eventDate {
            let next = reminders(for: event).first { calendar.startOfDay(for: $0) > calendar.startOfDay(for: now) }
            if let next {
                s.status = .away
                s.returnDate = next
            } else {
                // The day itself has been seen. Nothing left to remind.
                s.status = .kept
                s.returnDate = nil
            }
        }
        s.updatedAt = now
    }

    func done(_ s: Save, now: Date) {
        s.status = .kept
        s.returnDate = nil
        s.updatedAt = now
    }

    func later(_ s: Save, until date: Date, now: Date) {
        s.status = .away
        s.returnDate = date
        s.seenOn = nil
        s.updatedAt = now
    }

    func letGo(_ s: Save, now: Date) {
        s.deletedAt = now
        s.updatedAt = now
    }

    /// Pulled out of the Box by hand.
    func bringBack(_ s: Save, now: Date) {
        s.status = .today
        s.returnDate = nil
        s.seenOn = nil
        s.deletedAt = nil
        s.updatedAt = now
    }
}

/// A copy of the fields an action can change, so every action can be undone.
struct SaveSnapshot {
    let status: SaveStatus
    let returnDate: Date?
    let seenOn: Date?
    let deletedAt: Date?
    let updatedAt: Date

    init(_ s: Save) {
        status = s.status
        returnDate = s.returnDate
        seenOn = s.seenOn
        deletedAt = s.deletedAt
        updatedAt = s.updatedAt
    }

    func restore(_ s: Save) {
        s.status = status
        s.returnDate = returnDate
        s.seenOn = seenOn
        s.deletedAt = deletedAt
        s.updatedAt = updatedAt
    }
}

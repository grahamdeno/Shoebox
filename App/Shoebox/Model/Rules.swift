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

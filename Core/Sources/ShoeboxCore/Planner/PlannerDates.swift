import Foundation

// Date arithmetic for the planner: days, Issues, workdays, holidays, seasons.
// Weekday numbers follow Calendar: 1 = Sunday ... 7 = Saturday.

enum Holiday: Sendable, CaseIterable {
    case newYear, newYearsEve, valentines, easter, mothersDay, memorialDay, fathersDay, july4, laborDay,
         halloween, thanksgiving, christmasEve, christmas

    /// Days that are not workdays (R17 "first workday", R18).
    static let offWork: [Holiday] = [.newYear, .memorialDay, .july4, .laborDay, .thanksgiving, .christmas]
}

enum Season: Sendable, Equatable {
    case spring, summer, fall, winter

    /// Astronomical start, as a fixed month and day. [Check] Fall uses Sep 22 every year; in years
    /// when the equinox falls on Sep 23 the first Saturday is almost always the same.
    var start: (month: Int, day: Int) {
        switch self {
        case .spring: return (3, 20)
        case .summer: return (6, 21)
        case .fall: return (9, 22)
        case .winter: return (12, 21)
        }
    }
}

struct PlannerDates: Sendable {
    let cal: Calendar
    let settings: PlannerSettings

    // MARK: Days and times

    func day(_ d: Date) -> Date { cal.startOfDay(for: d) }

    func add(days n: Int, to d: Date) -> Date {
        cal.date(byAdding: .day, value: n, to: d) ?? d.addingTimeInterval(Double(n) * 86_400)
    }

    func add(_ component: Calendar.Component, _ n: Int, to d: Date) -> Date {
        cal.date(byAdding: component, value: n, to: d) ?? d
    }

    func at(_ t: DayTime, _ d: Date) -> Date {
        cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: d)
            ?? day(d).addingTimeInterval(Double(t.totalMinutes) * 60)
    }

    func time(_ d: Date) -> DayTime {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return DayTime(c.hour ?? 0, c.minute ?? 0)
    }

    func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) }

    func isWeekend(_ d: Date) -> Bool { let w = weekday(d); return w == 1 || w == 7 }

    func ymd(_ d: Date) -> (year: Int, month: Int, day: Int) {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// A valid calendar date at the start of its day, or nil (Feb 30).
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        guard let r = cal.date(from: c) else { return nil }
        let back = ymd(r)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return day(r)
    }

    func same(_ a: Date, _ b: Date) -> Bool { cal.isDate(a, inSameDayAs: b) }

    func daysBetween(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }

    /// The next day with weekday `w` after `d`: 1 to 7 days out, or 0 to 6 with `includeToday`.
    func next(weekday w: Int, from d: Date, includeToday: Bool = false) -> Date {
        var n = (w - weekday(d) + 7) % 7
        if n == 0 && !includeToday { n = 7 }
        return add(days: n, to: day(d))
    }

    func saturday(onOrAfter d: Date) -> Date { next(weekday: 7, from: d, includeToday: true) }

    func daysInMonth(_ y: Int, _ m: Int) -> Int {
        guard let first = date(y, m, 1), let r = cal.range(of: .day, in: .month, for: first) else { return 28 }
        return r.count
    }

    // MARK: The Issue

    func issueTime(_ d: Date) -> DayTime { isWeekend(d) ? settings.weekendIssue : settings.weekdayIssue }

    func issue(_ d: Date) -> Date { at(issueTime(d), d) }

    func nextIssue(atOrAfter d: Date) -> Date {
        let i = issue(d)
        return i >= d ? i : issue(add(days: 1, to: d))
    }

    // MARK: Workdays and holidays

    func nth(_ n: Int, weekday w: Int, month m: Int, year y: Int) -> Date? {
        guard let first = date(y, m, 1) else { return nil }
        let off = (w - weekday(first) + 7) % 7
        return date(y, m, 1 + off + (n - 1) * 7)
    }

    func last(weekday w: Int, month m: Int, year y: Int) -> Date? {
        let n = daysInMonth(y, m)
        guard let lastDay = date(y, m, n) else { return nil }
        let off = (weekday(lastDay) - w + 7) % 7
        return date(y, m, n - off)
    }

    /// Western Easter (anonymous Gregorian algorithm).
    func easter(_ y: Int) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let dayOfMonth = ((h + l - 7 * m + 114) % 31) + 1
        return date(y, month, dayOfMonth)
    }

    func holiday(_ h: Holiday, year y: Int) -> Date? {
        switch h {
        case .newYear: return date(y, 1, 1)
        case .newYearsEve: return date(y, 12, 31)
        case .valentines: return date(y, 2, 14)
        case .easter: return easter(y)
        case .mothersDay: return nth(2, weekday: 1, month: 5, year: y)
        case .memorialDay: return last(weekday: 2, month: 5, year: y)
        case .fathersDay: return nth(3, weekday: 1, month: 6, year: y)
        case .july4: return date(y, 7, 4)
        case .laborDay: return nth(1, weekday: 2, month: 9, year: y)
        case .halloween: return date(y, 10, 31)
        case .thanksgiving: return nth(4, weekday: 5, month: 11, year: y)
        case .christmasEve: return date(y, 12, 24)
        case .christmas: return date(y, 12, 25)
        }
    }

    /// The holiday's next date, today included.
    func nextHoliday(_ h: Holiday, from now: Date) -> Date? {
        let y = ymd(now).year
        if let x = holiday(h, year: y), x >= day(now) { return x }
        return holiday(h, year: y + 1)
    }

    func isOffWorkHoliday(_ d: Date) -> Bool {
        let y = ymd(d).year
        for h in Holiday.offWork {
            if let x = holiday(h, year: y), same(x, d) { return true }
        }
        return false
    }

    func isWorkday(_ d: Date) -> Bool { !isWeekend(d) && !isOffWorkHoliday(d) }

    func firstWorkday(onOrAfter d: Date) -> Date {
        var x = day(d)
        for _ in 0..<15 {
            if isWorkday(x) { return x }
            x = add(days: 1, to: x)
        }
        return day(d)
    }

    func lastWorkday(year y: Int, month m: Int) -> Date {
        guard let lastDay = date(y, m, daysInMonth(y, m)) else { return Date.distantPast }
        var x = lastDay
        for _ in 0..<15 {
            if isWorkday(x) { return x }
            x = add(days: -1, to: x)
        }
        return lastDay
    }

    // MARK: Seasons

    func season(of d: Date) -> Season {
        let p = ymd(d)
        let md = p.month * 100 + p.day
        if md >= 1221 || md < 320 { return .winter }
        if md < 621 { return .spring }
        if md < 922 { return .summer }
        return .fall
    }

    /// The season's next start strictly after today.
    func nextStart(of s: Season, after now: Date) -> Date {
        let y = ymd(now).year
        let today = day(now)
        for year in [y, y + 1, y + 2] {
            if let x = date(year, s.start.month, s.start.day), x > today { return x }
        }
        return add(days: 365, to: today)
    }
}

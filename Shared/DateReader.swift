import Foundation

/// Finds the date a post is about, in the post's own words, so it can come back at the right time.
/// Plain rules on the phone, no network. Only dates still ahead of the day the post was kept count:
/// a date already past is history, not an event.
struct DateMention: Equatable {
    var day: Date
    /// Hour and minute, when the words give a time ("4:00", "7pm").
    var time: DateComponents?
    /// "Forms due Nov 3": a date something has to be done by, rather than when it happens.
    var isDeadline: Bool
    /// The words around it, for showing why it was picked.
    var context: String
}

struct DateReading: Equatable {
    /// The day (with the time, when there is one) the post is about.
    var event: Date
    var hasTime: Bool
    /// Other dates in the words, earliest first, without the event's own day.
    var others: [Date]
}

enum DateReader {
    // MARK: Reading

    /// The date a post is about, or nil when its words name none still ahead.
    static func read(_ text: String, created: Date, calendar: Calendar = .current) -> DateReading? {
        let found = mentions(in: text, created: created, calendar: calendar)
        guard !found.isEmpty else { return nil }
        let event = found.first(where: { !$0.isDeadline }) ?? found[0]
        let others = found.filter { $0.day != event.day }.map(\.day)
        var seen = Set<Date>()
        let unique = others.filter { seen.insert($0).inserted }
        return DateReading(event: combine(event, calendar: calendar), hasTime: event.time != nil, others: unique)
    }

    /// Every date still ahead, earliest first.
    static func mentions(in raw: String, created: Date, calendar: Calendar = .current) -> [DateMention] {
        let text = stripLinks(raw)
        guard !text.isEmpty else { return [] }
        let start = calendar.startOfDay(for: created)
        let horizon = calendar.date(byAdding: .day, value: 400, to: start) ?? start
        var out: [DateMention] = []
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)

        // "October 30", "Oct. 30th", "November 7, 2026"
        for m in monthDay.matches(in: text, range: whole) {
            guard let month = monthNumber(ns.substring(with: m.range(at: 1))),
                  let day = Int(ns.substring(with: m.range(at: 2))), (1...31).contains(day) else { continue }
            var year: Int?
            if m.range(at: 3).location != NSNotFound { year = Int(ns.substring(with: m.range(at: 3))) }
            if let d = resolve(month: month, day: day, year: year, created: start, calendar: calendar) {
                out.append(make(d, m.range, ns, calendar))
            }
        }
        // "10/30" and "10/30/26" (month first)
        for m in numeric.matches(in: text, range: whole) {
            guard let month = Int(ns.substring(with: m.range(at: 1))), (1...12).contains(month),
                  let day = Int(ns.substring(with: m.range(at: 2))), (1...31).contains(day) else { continue }
            var year: Int?
            if m.range(at: 3).location != NSNotFound, var y = Int(ns.substring(with: m.range(at: 3))) {
                if y < 100 { y += 2000 }
                year = y
            }
            if let d = resolve(month: month, day: day, year: year, created: start, calendar: calendar) {
                out.append(make(d, m.range, ns, calendar))
            }
        }
        // "Friday", "next Tuesday": the next one, within two weeks
        for m in weekday.matches(in: text, range: whole) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            guard let index = weekdayNames.firstIndex(of: name) else { continue }
            let today = calendar.component(.weekday, from: start) - 1
            var add = (index - today + 7) % 7
            if add == 0 { add = 7 }
            if add <= 14, let d = calendar.date(byAdding: .day, value: add, to: start) {
                out.append(make(d, m.range, ns, calendar))
            }
        }

        let ahead = out.filter { $0.day >= start && $0.day <= horizon }
        // The same day named twice is one mention; keep the one that has a time.
        var byDay: [Date: DateMention] = [:]
        for m in ahead {
            if let old = byDay[m.day] {
                if old.time == nil && m.time != nil { byDay[m.day] = m }
                else if old.isDeadline && !m.isDeadline { byDay[m.day] = m }
            } else {
                byDay[m.day] = m
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    // MARK: Applying

    /// Reads a save's own words and fills in its event date, time and other dates.
    /// Pages are read by title, description and your note only (their long text names too many unrelated dates).
    /// Returns true when something was found.
    @discardableResult
    static func apply(to s: Save, calendar: Calendar = .current) -> Bool {
        guard s.eventDate == nil else { return false }
        var parts = [s.title, s.snippet, s.note]
        if s.kind != .link { parts.append(String(s.body.prefix(6_000))) }
        guard let r = read(parts.joined(separator: "\n"), created: s.createdAt, calendar: calendar) else { return false }
        s.eventDate = r.event
        s.eventHasTime = r.hasTime
        s.otherDates = r.others
        return true
    }

    // MARK: Pieces

    private static func make(_ day: Date, _ range: NSRange, _ ns: NSString, _ calendar: Calendar) -> DateMention {
        let before = ns.substring(with: NSRange(location: max(0, range.location - 56), length: min(56, range.location))).lowercased()
        let afterStart = range.location + range.length
        let after = ns.substring(with: NSRange(location: afterStart, length: min(70, ns.length - afterStart)))
        let deadline = deadlineWords.contains { before.contains($0) } || after.lowercased().prefix(22).contains("deadline")
        let around = ns.substring(with: NSRange(location: max(0, range.location - 30), length: min(ns.length - max(0, range.location - 30), range.length + 60)))
        return DateMention(day: calendar.startOfDay(for: day), time: time(around: range, in: ns), isDeadline: deadline,
                           context: around.replacingOccurrences(of: "\n", with: " "))
    }

    private static func combine(_ m: DateMention, calendar: Calendar) -> Date {
        guard let t = m.time, let h = t.hour else { return m.day }
        return calendar.date(bySettingHour: h, minute: t.minute ?? 0, second: 0, of: m.day) ?? m.day
    }

    /// The time of day for a date: the first time in the same sentence ("4:00 to 6:00 in the gym on October 30"),
    /// else the first one in the sentence right after it ("Dance is Oct 30. Doors open at 6.").
    private static func time(around range: NSRange, in ns: NSString) -> DateComponents? {
        let (from, to) = sentence(around: range, in: ns)
        if let t = firstClock(in: ns, from: from, to: to) { return t }
        let nextEnd = min(ns.length, to + 90)
        guard to < nextEnd else { return nil }
        let (nf, nt) = sentence(around: NSRange(location: min(to + 1, ns.length - 1), length: 0), in: ns)
        return firstClock(in: ns, from: nf, to: min(nt, nextEnd))
    }

    private static func sentence(around range: NSRange, in ns: NSString) -> (Int, Int) {
        func isBreak(_ i: Int) -> Bool {
            let c = ns.character(at: i)
            if c == 0x21 || c == 0x3F || c == 0x0A { return true }          // ! ? newline
            if c == 0x2E {                                                   // . followed by space or the end
                return i + 1 >= ns.length || CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(ns.character(at: i + 1)) ?? "x")
            }
            return false
        }
        var from = range.location
        while from > 0, !isBreak(from - 1) { from -= 1 }
        var to = range.location + range.length
        while to < ns.length, !isBreak(to) { to += 1 }
        return (from, min(ns.length, to))
    }

    private static func firstClock(in ns: NSString, from: Int, to: Int) -> DateComponents? {
        guard to > from else { return nil }
        let text = ns.substring(with: NSRange(location: from, length: to - from)) as NSString
        guard let m = clock.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
        if m.range(at: 5).location != NSNotFound { return DateComponents(hour: 12, minute: 0) }
        var hour = 0, minute = 0
        var suffix = ""
        if m.range(at: 1).location != NSNotFound {
            hour = Int(text.substring(with: m.range(at: 1))) ?? 0
            if m.range(at: 2).location != NSNotFound { minute = Int(text.substring(with: m.range(at: 2))) ?? 0 }
            if m.range(at: 3).location != NSNotFound { suffix = text.substring(with: m.range(at: 3)).lowercased() }
        } else if m.range(at: 4).location != NSNotFound {
            let parts = text.substring(with: m.range(at: 4)).split(separator: ":")
            hour = Int(parts[0]) ?? 0
            minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if suffix.hasPrefix("p"), hour < 12 { hour += 12 }
        else if suffix.hasPrefix("a"), hour == 12 { hour = 0 }
        else if suffix.isEmpty, (1...6).contains(hour) { hour += 12 }   // "4:00 to 6:00" is the afternoon
        return DateComponents(hour: hour, minute: minute)
    }

    /// A written month and day. With no year it is the next such day; one just passed (within a week) is history.
    private static func resolve(month: Int, day: Int, year: Int?, created start: Date, calendar: Calendar) -> Date? {
        var c = DateComponents()
        c.month = month; c.day = day
        if let year {
            c.year = year
            return calendar.date(from: c)
        }
        c.year = calendar.component(.year, from: start)
        guard let thisYear = calendar.date(from: c) else { return nil }
        if thisYear >= start { return thisYear }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        if thisYear >= weekAgo { return thisYear }   // just passed: stays in the past and is dropped
        c.year = (c.year ?? 0) + 1
        return calendar.date(from: c)
    }

    private static func stripLinks(_ s: String) -> String {
        links.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
    }

    private static func monthNumber(_ word: String) -> Int? {
        let k = word.lowercased().prefix(3)
        return ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex(of: String(k)).map { $0 + 1 }
    }

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let deadlineWords = ["due", "deadline", "by ", "before ", "no later", "register", "rsvp", "sign up", "sign-up",
                                        "submit", "last day", "closes", "close on", "expires", "return by", "turn in"]

    private static let monthDay = try! NSRegularExpression(
        pattern: #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#,
        options: [.caseInsensitive])
    private static let numeric = try! NSRegularExpression(pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?(?![\d/])"#)
    private static let weekday = try! NSRegularExpression(
        pattern: #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, options: [.caseInsensitive])
    private static let clock = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?![a-z])|\b(\d{1,2}:\d{2})\b|\b(noon)\b"#, options: [.caseInsensitive])
    private static let links = try! NSRegularExpression(pattern: #"https?://\S+|www\.\S+"#, options: [.caseInsensitive])
}

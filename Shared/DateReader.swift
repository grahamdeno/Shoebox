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
    static func read(_ text: String, created: Date, calendar: Calendar = .current, allowWeekdays: Bool = true) -> DateReading? {
        let found = mentions(in: text, created: created, calendar: calendar, allowWeekdays: allowWeekdays)
        guard !found.isEmpty else { return nil }
        let event = found.first(where: { !$0.isDeadline }) ?? found[0]
        let others = found.filter { $0.day != event.day }.map(\.day)
        var seen = Set<Date>()
        let unique = others.filter { seen.insert($0).inserted }
        return DateReading(event: combine(event, calendar: calendar), hasTime: event.time != nil, others: unique)
    }

    /// Every date still ahead, earliest first.
    static func mentions(in raw: String, created: Date, calendar: Calendar = .current, allowWeekdays: Bool = true) -> [DateMention] {
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
            // "1/2 cup sugar" and "Rated 4/5" are not dates.
            if year == nil, notADate(month: month, day: day, range: m.range, in: ns) { continue }
            if let d = resolve(month: month, day: day, year: year, created: start, calendar: calendar) {
                out.append(make(d, m.range, ns, calendar))
            }
        }
        // "Friday", "next Tuesday": the next one, within two weeks
        for m in weekday.matches(in: text, range: allowWeekdays ? whole : NSRange(location: 0, length: 0)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            guard let index = weekdayNames.firstIndex(of: name) else { continue }
            // "last Monday", "Black Friday", "every Tuesday" name no coming day.
            let lead = lastWord(before: m.range, in: ns)
            if ["last", "black", "every", "each", "past"].contains(lead) { continue }
            let today = calendar.component(.weekday, from: start) - 1
            var add = (index - today + 7) % 7
            // The weekday of the day it was kept means that day, unless it says "next".
            if add == 0, lead == "next" { add = 7 }
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
    /// `asOf` is for old saves read later: dates are then worked out from that day, not the day it was kept,
    /// so a date already gone by is never taken as an event.
    /// Only your own writing (notes, quotes, emails) is read in full. Your reason is read for written dates only,
    /// since "Read this Monday" is a reminder, not an event.
    @discardableResult
    static func apply(to s: Save, calendar: Calendar = .current, asOf: Date? = nil) -> Bool {
        guard s.eventDate == nil else { return false }
        let when = max(s.createdAt, asOf ?? s.createdAt)
        var parts = [s.title, s.snippet]
        if [.note, .quote, .email].contains(s.kind) { parts.append(String(s.body.prefix(6_000))) }
        var found = read(parts.joined(separator: "\n"), created: when, calendar: calendar)
        if found == nil, !s.note.isEmpty {
            found = read(s.note, created: when, calendar: calendar, allowWeekdays: false)
        }
        guard let r = found else { return false }
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
        let whole = NSRange(location: 0, length: text.length)
        let single = clock.firstMatch(in: text as String, range: whole)
        // "6-8pm" and "7:00 to 9:00 pm": the start takes the end's am or pm, and the start is the time.
        if let r = rangeClock.firstMatch(in: text as String, range: whole),
           single == nil || r.range.location <= single!.range.location {
            var h1 = Int(text.substring(with: r.range(at: 1))) ?? 0
            let m1 = r.range(at: 2).location != NSNotFound ? Int(text.substring(with: r.range(at: 2))) ?? 0 : 0
            let h2 = Int(text.substring(with: r.range(at: 3))) ?? 0
            let pm = text.substring(with: r.range(at: 5)).lowercased().hasPrefix("p")
            guard (1...12).contains(h1), (0...59).contains(m1) else { return nil }
            if pm {
                // "11-1pm" starts in the morning.
                if h1 < 12, !(h1 > h2 || h2 == 12) { h1 += 12 }
            } else if h1 == 12 {
                h1 = 0
            }
            return DateComponents(hour: h1, minute: m1)
        }
        guard let m = single else { return nil }
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
        else if suffix.isEmpty, (7...11).contains(hour) { return nil }  // "7:00" alone could be either: no time
        return DateComponents(hour: hour, minute: minute)
    }

    /// The word just before a match, lowercased.
    private static func lastWord(before range: NSRange, in ns: NSString) -> String {
        let from = max(0, range.location - 14)
        let s = ns.substring(with: NSRange(location: from, length: range.location - from)).lowercased()
        return s.split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
    }

    private static let fractions: Set<String> = ["1/2", "1/3", "2/3", "1/4", "3/4", "1/8", "3/8", "5/8", "7/8"]

    /// Fractions, amounts and ratings written like a date.
    private static func notADate(month: Int, day: Int, range: NSRange, in ns: NSString) -> Bool {
        let afterStart = range.location + range.length
        let after = ns.substring(with: NSRange(location: afterStart, length: min(12, ns.length - afterStart)))
            .lowercased().trimmingCharacters(in: .whitespaces)
        let units = ["cup", "tsp", "tbsp", "lb", "oz", "star", "pt ", "pts", "inch", "%", "mile", "hour", "hrs", "hr "]
        if units.contains(where: { after.hasPrefix($0) }) { return true }
        let lead = lastWord(before: range, in: ns)
        if ["rated", "rating", "score", "scored", "stars", "ratio", "page", "pg", "step", "chapter", "vol", "part", "grade", "gpa", "odds"].contains(lead) { return true }
        if fractions.contains("\(month)/\(day)") {
            return !["on", "by", "due", "before", "until", "through", "thru", "from", "starts", "date", "deadline"].contains(lead)
        }
        return false
    }

    /// A written month and day. With no year it is the next such day; one gone by in the last four months is history.
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
        let cutoff = calendar.date(byAdding: .day, value: -120, to: start) ?? start
        if thisYear >= cutoff { return thisYear }   // recently passed ("Recap of the Oct 12 meeting"): history, dropped
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
    private static let rangeClock = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(?:-|–|—|to|until)\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?![a-z])"#, options: [.caseInsensitive])
    private static let links = try! NSRegularExpression(pattern: #"https?://\S+|www\.\S+"#, options: [.caseInsensitive])
}

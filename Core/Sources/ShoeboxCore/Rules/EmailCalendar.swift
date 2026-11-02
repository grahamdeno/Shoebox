import Foundation

/// SPEC 7.6b: a newsletter or school notice with many dates becomes one post per date that matters to you.
/// Which dates matter comes from a short line in Settings ("Sam, 4th grade: soccer, band").
/// Everything here is plain rules, so the same email always makes the same posts and nothing is invented.
public enum EmailCalendar {
    /// Fewer dated lines than this is an ordinary email: one post.
    public static let minimumDates = 4

    public struct Item: Equatable, Sendable {
        /// The dated line as written, tidied.
        public var line: String
        /// The heading it sat under, if any ("8TH GRADE", "Athletics and activities").
        public var section: String?
        /// A short name for the post: the line without its date, up to the first comma or full stop.
        public var title: String
        public var day: Date
        public var link: URL?
    }

    /// Who your mail is about, read from your own words in Settings.
    public struct Profile: Equatable, Sendable {
        public var grades: Set<Int>
        public var words: [String]
        public var isEmpty: Bool { grades.isEmpty && words.isEmpty }

        public init(grades: Set<Int>, words: [String]) {
            self.grades = grades
            self.words = words
        }

        /// "Sam, 8th grade: cross country, band (trumpet), soccer, lacrosse" gives grade 8 and
        /// the words sam, cross country, band, trumpet, soccer, lacrosse.
        public init(_ text: String) {
            let lower = text.lowercased()
            grades = Set(EmailCalendar.grades(in: lower))
            let cleaned = lower.replacingOccurrences(of: #"\b\d{1,2}(st|nd|rd|th)\s*grade(rs)?\b"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\bgrade\s*\d{1,2}\b"#, with: " ", options: .regularExpression)
            let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ",;:()/\n|&+"))
                .flatMap { $0.components(separatedBy: " and ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            let skip: Set<String> = ["my", "son", "daughter", "kid", "kids", "child", "the", "plays", "does", "in", "on", "is", "a", "an", "me", "i", "he", "she", "they"]
            var seen = Set<String>()
            words = parts.compactMap { p in
                let w = p.split(separator: " ").filter { !skip.contains(String($0)) }.joined(separator: " ")
                guard w.count >= 3, seen.insert(w).inserted else { return nil }
                return w
            }
        }
    }

    /// Every line that names a calendar day (a month and day, or 11/14), with the heading above it.
    /// Weekday-only lines ("Tuesday 6 PM track") repeat every week, so they are not dates here.
    public static func items(in text: String, received: Date, calendar: Calendar) -> [Item] {
        var out: [Item] = []
        var section: String?
        var lastWasItem = false
        for raw in text.components(separatedBy: .newlines) {
            let line = tidy(raw)
            guard !line.isEmpty else { continue }
            // A line that starts in lowercase, or follows a line that stopped mid-sentence (no full stop), carries on
            // the one above: a PDF or a mail program wraps long lines. A new bullet or an ALL CAPS heading never does.
            let day = firstDay(in: line, received: received, calendar: calendar)
            let isBullet = raw.trimmingCharacters(in: .whitespaces).first.map { "-•*·–".contains($0) } ?? false
            let allCaps = line == line.uppercased() && line.contains(where: \.isLetter)
            let endsOpen = !(out.last?.line.last.map { ".!?".contains($0) } ?? true)
            let lowercase = line.first?.isLowercase ?? false
            if lastWasItem, !isBullet, lowercase || (day == nil && endsOpen && !allCaps) {
                if var last = out.popLast() { last.line += " " + line; out.append(last) }
                continue
            }
            if lowercase { continue }
            lastWasItem = false
            if let day {
                out.append(Item(line: line, section: section, title: title(of: line), day: day, link: link(in: line)))
                lastWasItem = true
            } else if isHeading(line) {
                section = line
            }
        }
        return out
    }

    /// The dates that matter to the profile. A line naming another grade is left out; a line naming one of
    /// your words is kept; under a heading for another grade, out; school-wide days (no school, early release,
    /// all grades) are kept; anything else under an activity heading is left out unless it names your words.
    /// With no profile, only school-wide days are kept.
    public static func relevant(_ items: [Item], to profile: Profile) -> [Item] {
        items.filter { keep($0, profile) }
    }

    static func keep(_ item: Item, _ profile: Profile) -> Bool {
        let line = item.line.lowercased()
        let section = (item.section ?? "").lowercased()
        let lineGrades = grades(in: line)
        if !lineGrades.isEmpty { return lineGrades.contains(where: profile.grades.contains) }
        if profile.words.contains(where: { contains(line, word: $0) }) { return true }
        let sectionGrades = grades(in: section)
        if !sectionGrades.isEmpty { return sectionGrades.contains(where: profile.grades.contains) }
        if schoolWide.contains(where: { line.contains($0) }) { return true }
        if item.section == nil || generalHeadings.contains(where: { section.contains($0) }) { return true }
        return false
    }

    static let schoolWide = ["no school", "early release", "school closed", "schools closed", "last day", "first day",
                             "winter break", "spring break", "thanksgiving break", "holiday break", "all students",
                             "all grades", "school-wide", "schoolwide", "all families", "report card", "conferences"]
    static let generalHeadings = ["all grades", "all students", "everyone", "school-wide", "schoolwide", "general",
                                  "reminders", "important dates", "calendar", "dates to remember", "dear", "upcoming", "families"]

    static func grades(in lower: String) -> [Int] {
        var out: [Int] = []
        for pattern in [#"\b(\d{1,2})(?:st|nd|rd|th)\s*grade"#, #"\bgrade\s*(\d{1,2})\b"#] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                if let r = Range(m.range(at: 1), in: lower), let n = Int(lower[r]), (1...12).contains(n) { out.append(n) }
            }
        }
        return out
    }

    /// Whole words, with hyphens and spaces alike and a plural allowed: "cross-country" finds "Cross country",
    /// "soccer" finds "Soccer:", "game" finds "games".
    static func contains(_ text: String, word: String) -> Bool {
        let flat = { (s: String) in s.replacingOccurrences(of: #"[-–—_]+"#, with: " ", options: .regularExpression) }
        let parts = flat(word).split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !parts.isEmpty else { return false }
        let pattern = "\\b" + parts.joined(separator: "\\s+") + "(s|es)?\\b"
        return flat(text).range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func tidy(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        while let f = s.first, "-•*>·–".contains(f) { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// A short line with no date and no sentence ending: "8TH GRADE", "Band and arts", "Athletics:".
    static func isHeading(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard words.count <= 6, line.count <= 48, !line.contains("http") else { return false }
        return !(line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?"))
    }

    static let monthNames: [String: Int] = {
        var m: [String: Int] = [:]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for (i, name) in f.monthSymbols.enumerated() { m[name.lowercased()] = i + 1 }
        for (i, name) in f.shortMonthSymbols.enumerated() { m[name.lowercased()] = i + 1 }
        m["sept"] = 9
        return m
    }()

    /// The first month-and-day ("Nov 7", "November 14th", "Dec. 6") or numeric date ("11/14") in the line.
    /// A day more than 60 days before the email arrived means next year.
    public static func firstDay(in line: String, received: Date, calendar: Calendar) -> Date? {
        let lower = line.lowercased().replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        let tokens = lower.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var found: (month: Int, day: Int, year: Int?)?
        for (i, tok) in tokens.enumerated() where i + 1 < tokens.count {
            guard let month = monthNames[tok] else { continue }
            let digits = tokens[i + 1].prefix { $0.isNumber }
            guard digits.count <= 2, let day = Int(digits), (1...31).contains(day) else { continue }
            var year: Int?
            if i + 2 < tokens.count, let y = Int(tokens[i + 2]), (2000...2100).contains(y) { year = y }
            found = (month, day, year)
            break
        }
        if found == nil, let re = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#),
           let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let mr = Range(m.range(at: 1), in: lower), let dr = Range(m.range(at: 2), in: lower),
           let month = Int(lower[mr]), let day = Int(lower[dr]), (1...12).contains(month), (1...31).contains(day) {
            var year: Int?
            if let yr = Range(m.range(at: 3), in: lower), let y = Int(lower[yr]) { year = y < 100 ? 2000 + y : y }
            found = (month, day, year)
        }
        guard let f = found else { return nil }
        var c = DateComponents()
        c.year = f.year ?? calendar.component(.year, from: received)
        c.month = f.month
        c.day = f.day
        guard var d = calendar.date(from: c) else { return nil }
        if f.year == nil, d < calendar.date(byAdding: .day, value: -60, to: received) ?? received {
            d = calendar.date(byAdding: .year, value: 1, to: d) ?? d
        }
        return calendar.startOfDay(for: d)
    }

    /// "Sat Nov 7: Cross country regional championship, 8:30 AM start" gives "Cross country regional championship".
    static func title(of line: String) -> String { pieces(of: line).title }

    /// A line taken apart: a short title (up to six words, cut at "for", "to", "at" when longer), what follows
    /// it as separate details, and the end of a date range written in front ("Nov 25 to 27" gives "27").
    static func pieces(of line: String) -> (title: String, details: [String], rangeEnd: String?) {
        var s = line
        var rangeEnd: String?
        // Drop a leading date ("Mon Nov 2:", "Nov 25 to 27:", "11/14 -") when a colon or dash follows it.
        if let r = s.range(of: #"^[^:]{0,24}?\d{1,2}(?:st|nd|rd|th)?(?:\s*(?:to|-|–)\s*(\d{1,2}))?\s*[:\-–]\s+"#, options: .regularExpression) {
            let prefix = String(s[r])
            if let e = prefix.range(of: #"(?:to|-|–)\s*\d{1,2}"#, options: .regularExpression) {
                rangeEnd = String(prefix[e]).filter(\.isNumber)
            }
            s = String(s[r.upperBound...])
        }
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        var rest = ""
        if let cut = s.range(of: #"(, |\. | - | – |; )"#, options: .regularExpression) {
            rest = String(s[cut.upperBound...])
            s = String(s[..<cut.lowerBound])
        }
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".:,-")))
        var details: [String] = []
        // Long names are cut at their first "for", "to", "at", "with" or "on"; the tail becomes a detail.
        if s.split(separator: " ").count > 6,
           let p = s.range(of: #" (for|to|at|with|on) "#, options: .regularExpression),
           s[..<p.lowerBound].split(separator: " ").count >= 2 {
            details.append(String(s[p.lowerBound...]).trimmingCharacters(in: .whitespaces))
            s = String(s[..<p.lowerBound])
        }
        // A time in the name ("Early release at 12:30 PM") is a detail, not part of the title.
        if let t = s.range(of: #"\s+(?:at|by|from|starts?|starting)?\s*\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b.*$"#,
                           options: [.regularExpression, .caseInsensitive]),
           s[..<t.lowerBound].split(separator: " ").count >= 1 {
            let tail = String(s[t]).trimmingCharacters(in: .whitespaces)
            let time = tail.replacingOccurrences(of: #"^(?:at|by|from|starts?|starting)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            details.append(time)
            s = String(s[..<t.lowerBound])
        }
        let words = s.split(separator: " ")
        if words.count > 7 { s = words.prefix(7).joined(separator: " ") }
        details += rest.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty }
        details = details.map { d in d.prefix(1).uppercased() + d.dropFirst() }
        guard let first = s.first else { return (line, [], nil) }
        return (first.uppercased() + s.dropFirst(), details, rangeEnd)
    }

    /// The words of a dated post: "Saturday, Nov 14 · 5:00 PM · Cafeteria · Potluck." The day comes first,
    /// spelled out; pieces that only repeat the date are left out.
    public static func details(of item: Item, received: Date, calendar: Calendar) -> String {
        let p = pieces(of: item.line)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE, MMM d"
        var day = f.string(from: item.day)
        if let end = p.rangeEnd, let n = Int(end) {
            var c = calendar.dateComponents([.year, .month], from: item.day)
            c.day = n
            if let endDay = calendar.date(from: c), endDay > item.day { day += " to " + f.string(from: endDay) }
        }
        let weekdays = Set(f.weekdaySymbols.map { $0.lowercased() })
        let kept = p.details.filter { d in
            firstDay(in: d, received: received, calendar: calendar) == nil && !weekdays.contains(d.lowercased())
        }
        return ([day] + kept).joined(separator: " · ") + "."
    }

    /// A short name for where the dates came from: "Roosevelt Middle School Family Newsletter, November 2026"
    /// gives "Roosevelt newsletter". Months, years, dates and words like "family" or "weekly" are dropped.
    public static func sourceName(_ subject: String) -> String {
        let drop: Set<String> = ["family", "families", "weekly", "monthly", "update", "updates", "the", "pdf", "middle", "elementary",
                                 "high", "school", "news", "for", "and", "of", "your", "our", "week", "issue", "edition"]
        let words = EmailRules.cleanSubject(subject)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && monthNames[$0.lowercased()] == nil && !$0.allSatisfy(\.isNumber) }
        let kept = words.filter { !drop.contains($0.lowercased()) }
        if let n = kept.firstIndex(where: { $0.lowercased() == "newsletter" }) {
            return n > 0 ? "\(kept[0]) newsletter" : "a newsletter"
        }
        let name = kept.prefix(3).joined(separator: " ")
        return name.isEmpty ? "via your Shoebox email" : name
    }

    /// The same event under slightly different words: "Winter band concert" and "Winter Band Concert, gym".
    /// Most of the shorter name's words (numbers and times aside) must appear in the other.
    public static func sameEvent(_ a: String, _ b: String) -> Bool {
        let wa = eventWords(a), wb = eventWords(b)
        guard !wa.isEmpty, !wb.isEmpty else { return false }
        let shared = wa.intersection(wb).count
        return Double(shared) / Double(min(wa.count, wb.count)) >= 0.6
    }

    static func eventWords(_ s: String) -> Set<String> {
        let skip: Set<String> = ["the", "a", "an", "and", "of", "for", "to", "at", "in", "on", "am", "pm", "with", "is", "are", "be"]
        let flat = s.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return Set(String(flat).split(separator: " ").map(String.init).filter { !skip.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    /// Clock times in a line, as written: "6:30 PM", "7 pm", "8:15 a.m.".
    public static func times(in line: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)"#, options: .caseInsensitive) else { return [] }
        return re.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { m in
            Range(m.range, in: line).map { String(line[$0]).uppercased().replacingOccurrences(of: ".", with: "") }
        }
    }

    /// What a resent line changed that you would want to see: a different time. Returns "6:30 PM to 7:00 PM".
    public static func timeChange(from old: String, to new: String) -> String? {
        let before = times(in: old), after = times(in: new)
        guard !after.isEmpty, before != after else { return nil }
        return before.isEmpty ? nil : "\(before.joined(separator: ", ")) to \(after.joined(separator: ", "))"
    }

    static func link(in line: String) -> URL? {
        guard let r = line.range(of: #"https?://[^\s)>\]]+"#, options: .regularExpression) else { return nil }
        let s = String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
        return URL(string: s)
    }
}

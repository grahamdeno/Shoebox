import Foundation

/// SPEC 7.6b: a newsletter or school notice with many dates becomes one post per date that matters to you.
/// Which dates matter comes from a short line in Settings ("Gunner, 8th grade: cross country, band, trumpet").
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

        /// "Gunner, 8th grade: cross country, band (trumpet), soccer, lacrosse" gives grade 8 and
        /// the words gunner, cross country, band, trumpet, soccer, lacrosse.
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
            // A line that starts in lowercase, or follows a line left open on a comma, carries on the one above
            // (a PDF or a mail program wraps long lines).
            let day = firstDay(in: line, received: received, calendar: calendar)
            let open = lastWasItem && day == nil && (out.last?.line.hasSuffix(",") ?? false)
            if let f = line.first, f.isLowercase || open {
                if lastWasItem, var last = out.popLast() { last.line += " " + line; out.append(last) }
                continue
            }
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
    static func title(of line: String) -> String {
        var s = line
        // Drop a leading date ("Mon Nov 2:", "Nov 25 to 27:", "11/14 -") when a colon or dash follows it.
        if let r = s.range(of: #"^[^:]{0,24}?\d{1,2}(?:st|nd|rd|th)?(?:\s*(?:to|-|–)\s*\d{1,2})?\s*[:\-–]\s+"#, options: .regularExpression) {
            s = String(s[r.upperBound...])
        }
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        if let cut = s.range(of: #"(, |\. | - | – )"#, options: .regularExpression) { s = String(s[..<cut.lowerBound]) }
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".:,-")))
        if s.count > 60 {
            let words = s.prefix(60).split(separator: " ").dropLast()
            s = words.joined(separator: " ")
        }
        guard let first = s.first else { return line }
        return first.uppercased() + s.dropFirst()
    }

    static func link(in line: String) -> URL? {
        guard let r = line.range(of: #"https?://[^\s)>\]]+"#, options: .regularExpression) else { return nil }
        let s = String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
        return URL(string: s)
    }
}

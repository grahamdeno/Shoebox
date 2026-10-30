import Foundation

// Reading the reason: words, phrases and the few patterns that need a regular expression.
// Everything here is plain text work; no dates are computed.

enum PartOfDay: Sendable, Equatable { case morning, lunch, afternoon, evening, dinner, bed }

enum RelativeUnit: Sendable, Equatable { case minute, hour, day, week, month, year }

struct RelativeTime: Sendable, Equatable { var amount: Int; var unit: RelativeUnit }

enum Meridiem: Sendable, Equatable { case am, pm }

struct ClockTime: Sendable, Equatable { var hour: Int; var minute: Int; var meridiem: Meridiem? }

enum MonthWhich: Sendable, Equatable { case thisMonth, nextMonth, named(Int) }

enum MonthPart: Sendable, Equatable { case start, mid, end }

struct MonthSpec: Sendable, Equatable { var which: MonthWhich; var part: MonthPart; var forceNext: Bool }

struct SeasonSpec: Sendable, Equatable { var season: Season; var next: Bool }

enum DateMatch: Sendable, Equatable {
    case monthDay(month: Int, day: Int, year: Int?)
    case dayOnly(Int)
}

/// The words of an R3 anchor phrase, after "before", "for", "at", "when", "ahead of", "during".
struct AnchorQuery: Sendable, Equatable {
    var keywords: [String] = []
    var weekday: Int? = nil
    var dayOffset: Int? = nil
    var generic = false
}

struct PlannerText: Sendable {
    let raw: String
    let norm: String
    let toks: [String]

    init(_ s: String) {
        raw = s
        norm = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        toks = PlannerText.tokens(s)
    }

    var isEmpty: Bool { toks.isEmpty }

    // MARK: Tokens

    /// Lowercased words. "Sam's" -> "sam", "I'm" -> "im", "12/3" -> "12", "3".
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                cur.append(ch)
            } else if ch == "'" || ch == "\u{2019}" || ch == "\u{2018}" {
                cur.append("'")
            } else {
                if let w = clean(cur) { out.append(w) }
                cur = ""
            }
        }
        if let w = clean(cur) { out.append(w) }
        return out
    }

    private static func clean(_ w: String) -> String? {
        var s = w
        if s.hasSuffix("'s") { s.removeLast(2) }
        s = s.replacingOccurrences(of: "'", with: "")
        return s.isEmpty ? nil : s
    }

    func has(_ phrase: String) -> Bool { index(of: phrase) != nil }

    func hasAny(_ phrases: [String]) -> Bool { phrases.contains { has($0) } }

    func index(of phrase: String) -> Int? {
        let p = PlannerText.tokens(phrase)
        guard !p.isEmpty, p.count <= toks.count else { return nil }
        for i in 0...(toks.count - p.count) where toks[i..<(i + p.count)].elementsEqual(p) {
            return i
        }
        return nil
    }

    // MARK: Regular expressions (NSRegularExpression, built per call: it is not Sendable)

    static func match(_ pattern: String, _ s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: range) else { return nil }
        var out: [String?] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: s) { out.append(String(s[r])) } else { out.append(nil) }
        }
        return out
    }

    static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }

    static func group(_ m: [String?], _ i: Int) -> String? { i < m.count ? m[i] : nil }

    // MARK: Word lists

    static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "tues": 3, "tue": 3, "wednesday": 4, "weds": 4,
        "thursday": 5, "thurs": 5, "thu": 5, "friday": 6, "fri": 6, "saturday": 7,
    ]

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    static let monthPattern =
        "(january|february|march|april|may|june|july|august|september|october|november|december|sept|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)"

    static func monthNumber(_ s: String?) -> Int? {
        guard let s else { return nil }
        return months[s.lowercased().replacingOccurrences(of: ".", with: "")]
    }

    static let anchorTriggers: Set<String> = ["before", "for", "at", "when", "during"]

    static let breakers: Set<String> = ["so", "because", "since", "then", "but", "and", "if", "which", "or"]

    static let genericEventWords: Set<String> = ["meeting", "meetings", "mtg", "event", "appointment", "appt", "call"]

    /// Words that never name a calendar event in an R3 match: grammar, time and place words, verbs
    /// that come before the topic, and holidays (R16 owns those even when a holiday calendar is on).
    static let anchorStopWords: Set<String> = Set([
        "a", "an", "the", "this", "that", "these", "those", "it", "its", "we", "i", "im", "you", "he", "she",
        "they", "our", "my", "your", "his", "her", "their", "us", "me", "them", "him", "to", "of", "on", "in",
        "at", "for", "with", "from", "by", "about", "into", "over", "up", "down", "out", "off", "is", "are",
        "was", "were", "be", "been", "am", "do", "does", "did", "will", "would", "can", "could", "should",
        "get", "gets", "got", "comes", "come", "coming", "came", "goes", "go", "going", "when", "before",
        "after", "ahead", "during", "while", "next", "last", "upcoming", "week", "weekend", "month", "year",
        "day", "days", "time", "morning", "afternoon", "evening", "night", "tonight", "lunch", "dinner",
        "supper", "home", "house", "work", "office", "team", "kids", "family", "read", "watch", "listen",
        "bring", "show", "share", "discuss", "mention", "raise", "ask", "tell", "talk", "prep", "prepare",
        "remember", "look", "check", "use", "try", "make", "start", "again", "some", "any", "all", "there",
        "here", "just", "really", "maybe", "have", "has", "had", "need", "needs", "want", "back", "thing",
        "stuff", "around", "ready", "first", "big", "new", "christmas", "xmas", "thanksgiving",
        "easter", "halloween", "valentine", "valentines", "eve", "holiday", "holidays", "gift", "gifts",
        "idea", "ideas", "present", "presents",
    ])

    static let tripWords: Set<String> = [
        "trip", "vacation", "travel", "traveling", "travelling", "getaway", "camping", "cruise", "away",
        "ooo", "pto", "holiday", "retreat",
    ]

    static let flightTitleWords: Set<String> = ["flight", "flights", "fly", "flying", "plane", "airport"]

    static let flightReasonWords = ["plane", "airplane", "flight", "flights", "fly", "flying", "airport", "in the air"]

    static let deadlineWords = [
        "by", "due", "register", "registration", "sign up", "signup", "before", "deadline", "rsvp", "apply",
        "enroll", "submit", "expires", "last day",
    ]

    static let workPhrases = [
        "at work", "for work", "to work", "at the office", "in the office", "the office", "for the team",
        "with the team", "the team", "my team", "our team",
    ]

    static let placePhrases = [
        "costco", "the store", "a store", "grocery", "groceries", "the mall", "walmart", "home depot", "lowes",
        "trader joe", "whole foods", "pharmacy", "hardware store", "downtown", "when im at", "when im in",
        "when i am at", "when i am in", "next time im", "next time i am", "errand", "errands", "sams club",
        "target store",
    ]

    static let somedayPhrases = [
        "someday", "some day", "eventually", "one day", "sometime", "some time", "at some point", "no rush",
        "whenever", "one of these days",
    ]

    static let unplaceableWords = ["when", "once", "after", "next time", "as soon as", "until"]

    static let giftOrTravelWords: Set<String> = [
        "gift", "gifts", "present", "presents", "wishlist", "travel", "trip", "flight", "flights", "ticket",
        "tickets", "hotel", "shipping", "order",
    ]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
        "forty-five": 45, "forty five": 45, "a couple": 2, "a couple of": 2, "couple": 2, "couple of": 2,
        "a few": 3, "few": 3,
    ]

    // MARK: What the reason says

    var weekday: Int? {
        for w in toks { if let n = PlannerText.weekdays[w] { return n } }
        return nil
    }

    var partOfDay: PartOfDay? {
        if hasAny(["bed", "bedtime", "asleep", "late tonight", "later tonight", "late at night"]) { return .bed }
        if hasAny(["dinner", "supper", "after work"]) { return .dinner }
        if hasAny(["lunch", "lunchtime", "midday"]) { return .lunch }
        if has("afternoon") { return .afternoon }
        if hasAny(["morning", "breakfast"]) { return .morning }
        if hasAny(["evening", "night", "tonight"]) { return .evening }
        return nil
    }

    var namesToday: Bool {
        hasAny(["today", "tonight", "this morning", "this afternoon", "this evening"])
    }

    var isRecurring: Bool {
        if hasAny(["daily", "weekly", "monthly", "nightly", "everyday", "weekdays", "weekends", "mondays",
                   "tuesdays", "wednesdays", "thursdays", "fridays", "saturdays", "sundays"]) { return true }
        let units: Set<String> = ["day", "morning", "night", "evening", "week", "weekend", "month", "year",
                                  "other", "weekday", "sunday", "monday", "tuesday", "wednesday", "thursday",
                                  "friday", "saturday", "afternoon", "quarter"]
        for i in toks.indices where (toks[i] == "every" || toks[i] == "each") && i + 1 < toks.count {
            if units.contains(toks[i + 1]) { return true }
        }
        return false
    }

    /// The reason with its recurring words taken out: "Every Monday" -> "monday".
    static func removingRecurring(_ s: String) -> String {
        var x = s.lowercased()
        x = replace("\\b(every|each)\\s+(other\\s+)?", in: x, with: "")
        x = replace("\\b(daily|weekly|monthly|nightly|everyday)\\b", in: x, with: "")
        x = replace("\\b(sun|mon|tues|wednes|thurs|fri|satur)days\\b", in: x, with: "$1day")
        x = replace("\\bweekends\\b", in: x, with: "weekend")
        x = replace("\\bweekdays\\b", in: x, with: "")
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasGiftWord: Bool {
        if hasAny(["gift", "gifts", "presents", "a present", "birthday present", "stocking stuffer", "stocking stuffers"]) {
            return true
        }
        return has("birthday") && has("for")
    }

    var hasWorkWord: Bool { hasAny(PlannerText.workPhrases) }

    var hasHomeWord: Bool {
        if hasAny(["home depot", "home goods"]) && !hasAny(["at home", "dinner"]) { return false }
        if hasAny(["dinner", "supper", "home", "kids", "kid", "children", "family", "wife", "husband", "partner",
                   "after work"]) { return true }
        return has("show") && hasAny(["mom", "dad", "son", "daughter", "parents", "grandma", "grandpa"])
    }

    var hasPlaceWord: Bool { hasAny(PlannerText.placePhrases) }

    var isSomeday: Bool { hasAny(PlannerText.somedayPhrases) }

    var isUnplaceable: Bool { hasAny(PlannerText.unplaceableWords) }

    var hasDeadlineWord: Bool { hasAny(PlannerText.deadlineWords) }

    var hasLeadWord: Bool { hasAny(["before", "for", "ahead of", "by", "in time for"]) }

    var isSchoolBreak: Bool {
        hasAny(["spring break", "winter break", "fall break", "summer break", "school break", "mid winter break"])
    }

    var holiday: Holiday? {
        if hasAny(["christmas eve", "xmas eve"]) { return .christmasEve }
        if hasAny(["christmas", "xmas"]) { return .christmas }
        if has("thanksgiving") { return .thanksgiving }
        if hasAny(["new year eve", "new years eve"]) { return .newYearsEve }
        if hasAny(["new year", "new years"]) { return .newYear }
        if hasAny(["fourth of july", "independence day", "july fourth"]) { return .july4 }
        if has("memorial day") { return .memorialDay }
        if has("labor day") { return .laborDay }
        if has("easter") { return .easter }
        if has("halloween") { return .halloween }
        if hasAny(["valentine", "valentines"]) { return .valentines }
        if hasAny(["mother day", "mothers day"]) { return .mothersDay }
        if hasAny(["father day", "fathers day"]) { return .fathersDay }
        return nil
    }

    var season: SeasonSpec? {
        let words: [String: Season] = ["spring": .spring, "summer": .summer, "fall": .fall, "autumn": .fall, "winter": .winter]
        let quals: Set<String> = ["this", "next", "the", "in", "during", "by", "until", "early", "late", "come",
                                  "coming", "before"]
        for i in toks.indices {
            guard let s = words[toks[i]] else { continue }
            if i + 1 < toks.count && toks[i + 1] == "break" { continue }
            let prev = i > 0 ? toks[i - 1] : ""
            if quals.contains(prev) || toks.count == 1 { return SeasonSpec(season: s, next: prev == "next") }
        }
        return nil
    }

    var monthSpec: MonthSpec? {
        if hasAny(["end of next month"]) { return MonthSpec(which: .nextMonth, part: .end, forceNext: false) }
        if hasAny(["end of the month", "end of month", "end of this month", "month end"]) {
            return MonthSpec(which: .thisMonth, part: .end, forceNext: false)
        }
        if hasAny(["next month"]) { return MonthSpec(which: .nextMonth, part: .start, forceNext: false) }
        if hasAny(["this month", "later this month"]) { return MonthSpec(which: .thisMonth, part: .start, forceNext: false) }
        let preps: Set<String> = ["in", "this", "next", "by", "during", "early", "late", "mid", "until", "of",
                                  "before", "around"]
        for i in toks.indices {
            guard let m = PlannerText.months[toks[i]], i > 0 else { continue }
            let prev = toks[i - 1]
            guard preps.contains(prev) else { continue }
            if toks[i] == "may" && (prev == "this" || prev == "of" && !(i >= 2 && toks[i - 2] == "end")) { continue }
            var part = MonthPart.start
            if prev == "late" || (prev == "of" && i >= 2 && toks[i - 2] == "end") { part = .end }
            if prev == "mid" { part = .mid }
            return MonthSpec(which: .named(m), part: part, forceNext: prev == "next")
        }
        return nil
    }

    // MARK: Patterns

    /// R1: "7pm", "7:30 p.m.", "at 3", "at 15:30", "noon".
    var clock: ClockTime? {
        let mer = "(a\\.?m\\.?|p\\.?m\\.?)"
        if let m = PlannerText.match("\\b(\\d{1,2})(?::(\\d{2}))?\\s*" + mer + "(?![a-z])", norm),
           let h = Int(PlannerText.group(m, 1) ?? ""), (1...12).contains(h) {
            let mm = Int(PlannerText.group(m, 2) ?? "0") ?? 0
            let pm = (PlannerText.group(m, 3) ?? "").hasPrefix("p")
            if (0...59).contains(mm) { return ClockTime(hour: h, minute: mm, meridiem: pm ? .pm : .am) }
        }
        let notAfter = "(?![\\d/:])(?!\\s*(?:st\\b|nd\\b|rd\\b|th\\b|days?\\b|weeks?\\b|months?\\b|years?\\b|hours?\\b|hrs?\\b|minutes?\\b|mins?\\b|people\\b|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))"
        if let m = PlannerText.match("\\b(?:at|around)\\s+(\\d{1,2})(?::(\\d{2}))?" + notAfter, norm),
           let h = Int(PlannerText.group(m, 1) ?? ""), (0...23).contains(h) {
            let mm = Int(PlannerText.group(m, 2) ?? "0") ?? 0
            if (0...59).contains(mm) { return ClockTime(hour: h, minute: mm, meridiem: nil) }
        }
        if has("noon") { return ClockTime(hour: 12, minute: 0, meridiem: .pm) }
        return nil
    }

    /// R2: "in an hour", "in 2 weeks", "three days from now", "in half an hour".
    var relative: RelativeTime? {
        if has("half an hour") { return RelativeTime(amount: 30, unit: .minute) }
        let num = "(a couple of|a couple|couple of|couple|a few|few|an|a|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty-five|forty five|\\d{1,3})"
        let unit = "(minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)"
        let m = PlannerText.match("\\bin\\s+" + num + "\\s+" + unit + "\\b", norm)
            ?? PlannerText.match("\\b" + num + "\\s+" + unit + "\\s+from\\s+(?:now|today)\\b", norm)
        guard let m, let n = PlannerText.group(m, 1), let u = PlannerText.group(m, 2) else { return nil }
        let amount = Int(n) ?? PlannerText.numberWords[n] ?? 1
        guard amount > 0 else { return nil }
        let unitValue: RelativeUnit
        if u.hasPrefix("min") { unitValue = .minute }
        else if u.hasPrefix("h") { unitValue = .hour }
        else if u.hasPrefix("d") { unitValue = .day }
        else if u.hasPrefix("w") { unitValue = .week }
        else if u.hasPrefix("mo") { unitValue = .month }
        else { unitValue = .year }
        return RelativeTime(amount: amount, unit: unitValue)
    }

    /// R6: "Nov 20", "November 20th, 2027", "20 Nov", "12/3", "the 20th".
    var dateMatch: DateMatch? {
        let mp = PlannerText.monthPattern
        if let m = PlannerText.match("\\b" + mp + "\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?![\\d:])(?:,?\\s+(\\d{4}))?", norm),
           let mon = PlannerText.monthNumber(PlannerText.group(m, 1)), let d = Int(PlannerText.group(m, 2) ?? "") {
            return .monthDay(month: mon, day: d, year: Int(PlannerText.group(m, 3) ?? ""))
        }
        if let m = PlannerText.match("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?" + mp + "\\b", norm),
           let d = Int(PlannerText.group(m, 1) ?? ""), let mon = PlannerText.monthNumber(PlannerText.group(m, 2)) {
            return .monthDay(month: mon, day: d, year: nil)
        }
        if let m = PlannerText.match("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?(?![\\d/])", norm),
           let mon = Int(PlannerText.group(m, 1) ?? ""), let d = Int(PlannerText.group(m, 2) ?? "") {
            var year: Int? = nil
            if let y = Int(PlannerText.group(m, 3) ?? "") { year = y < 100 ? 2000 + y : y }
            return .monthDay(month: mon, day: d, year: year)
        }
        if let m = PlannerText.match("\\bthe\\s+(\\d{1,2})(?:st|nd|rd|th)\\b", norm), let d = Int(PlannerText.group(m, 1) ?? "") {
            return .dayOnly(d)
        }
        return nil
    }

    // MARK: R3 anchor phrases

    /// The words after each anchor trigger, up to a clause break.
    var anchorPhrases: [[String]] {
        var out: [[String]] = []
        for i in toks.indices {
            var startIndex: Int? = nil
            if PlannerText.anchorTriggers.contains(toks[i]) { startIndex = i + 1 }
            else if toks[i] == "ahead", i + 1 < toks.count, toks[i + 1] == "of" { startIndex = i + 2 }
            guard let st = startIndex, st < toks.count else { continue }
            var phrase: [String] = []
            for w in toks[st...] {
                if PlannerText.breakers.contains(w) { break }
                phrase.append(w)
            }
            if !phrase.isEmpty { out.append(phrase) }
        }
        return out
    }

    static func query(_ phrase: [String]) -> AnchorQuery {
        var q = AnchorQuery()
        for w in phrase {
            if let wd = weekdays[w] { q.weekday = wd; continue }
            if w == "tomorrow" { q.dayOffset = 1; continue }
            if w == "today" || w == "tonight" { q.dayOffset = 0; continue }
            if genericEventWords.contains(w) { q.generic = true; continue }
            if anchorStopWords.contains(w) || w.count < 2 || Int(w) != nil { continue }
            q.keywords.append(w)
        }
        return q
    }

    /// Word match with light stemming: plan ~ planning, quarter ~ quarterly, review ~ reviews.
    static func wordsMatch(_ a: String, _ b: String) -> Bool {
        let x = stem(a), y = stem(b)
        if x == y { return true }
        let shorter = x.count <= y.count ? x : y
        let longer = x.count <= y.count ? y : x
        return shorter.count >= 4 && longer.hasPrefix(shorter)
    }

    private static func stem(_ w: String) -> String {
        var s = w
        if s.count > 4 && s.hasSuffix("s") { s.removeLast() }
        return s
    }
}

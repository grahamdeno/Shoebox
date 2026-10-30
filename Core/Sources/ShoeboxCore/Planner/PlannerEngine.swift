import Foundation

// The rules of docs/SPEC.md 4.3, applied in order. The first that matches wins.
//
// Order as run (SPEC order, with these changes, each so the examples in 4.4 come out right):
//   R22 is checked first, because "Every Monday" also reads as R7; its one moment is planned from
//       the rest of the words.
//   R1, R2, then R4 and R5 before R3: "for the flight" and "Gift idea for Sam's birthday" would
//       otherwise be taken by R3's calendar match (example 24 is R5).
//   R6, then R18 before R7: "Monday at work" is R18 on the day named (example 36).
//   R7, R8, R9 are one step: a day word and a part of day combine ("tomorrow at lunch").
//   R11 to R17, then R10: a stronger time word ("this weekend", "next week") beats home words. [Check]
//   R19, then "someday" (R20), then R21, then R20.

enum PlannerStage: Sendable, Equatable { case rules, someday, unplaceable, content }

struct PlannerEngine {
    let input: PlanInput
    let s: PlannerSettings
    let d: PlannerDates
    let t: PlannerText
    let now: Date
    let today: Date

    static let lunch = DayTime(12, 15)
    static let afternoon = DayTime(15, 30)
    static let tonight = DayTime(19, 30)
    static let weekendEvening = DayTime(19, 30)
    static let saturdayAfternoon = DayTime(14, 0)
    static let errand = DayTime(10, 30)
    static let quietStart = DayTime(21, 0)
    static let lastMinute = DayTime(23, 59)
    static let dailyBudget = 4

    init(_ input: PlanInput, _ settings: PlannerSettings, _ calendar: Calendar) {
        self.input = input
        self.s = settings
        self.d = PlannerDates(cal: calendar, settings: settings)
        self.t = PlannerText(input.reason)
        self.now = input.now
        self.today = calendar.startOfDay(for: input.now)
    }

    var hints: ModelHints { input.hints ?? ModelHints() }

    var minutes: Int {
        if let m = input.minutes, m > 0 { return m }
        switch input.kind {
        case .note, .quote, .photo: return 1
        case .link: return 6
        case .pdf: return 15
        case .video: return 10
        case .file: return 5
        }
    }

    var isWatch: Bool { input.intent == .watch || (input.intent == nil && input.kind == .video) }

    var upcoming: [CalendarEventInfo] {
        let limit = d.add(days: 60, to: now)
        return input.events.filter { $0.start > now && $0.start <= limit }.sorted { $0.start < $1.start }
    }

    // MARK: Evaluate

    func evaluate(allowRecurring: Bool = true) -> (outcome: PlanOutcome, stage: PlannerStage) {
        if t.isEmpty { return (.moment(finish(contentDraft())), .content) }

        if allowRecurring && t.isRecurring {
            let rest = PlannerText.removingRecurring(input.reason)
            var sub = input
            sub.reason = rest
            let inner = PlannerEngine(sub, s, d.cal).evaluate(allowRecurring: false)
            var m: PlannedMoment
            if rest.isEmpty || inner.stage == .content || inner.stage == .unplaceable {
                m = finish(Draft(start: d.nextIssue(atOrAfter: now), rule: "R22"))
            } else {
                m = inner.outcome.moment
            }
            m.ruleId = "R22"
            return (.offerReminder(fallback: m), .rules)
        }

        if let x = firstRule() { return (.moment(finish(x)), .rules) }
        if t.isSchoolBreak {
            // R16: school dates come from school posts (phase 5); until then, ask once.
            var fb = contentDraft()
            fb.rule = "R16"; fb.confidence = .guess
            return (.ask(choices: ["This weekend", "Next month", "Pick a date"], fallback: finish(fb)), .rules)
        }
        if let x = laterRule() { return (.moment(finish(x)), .rules) }
        if t.isSomeday { return (.moment(finish(somedayDraft())), .someday) }
        if t.isUnplaceable { return (r21(), .unplaceable) }
        if let m = hints.monthHint, (1...12).contains(m) {
            // The model read a month from words the rules don't know.
            return (.moment(finish(Draft(start: monthStart(.named(m), part: .start, forceNext: false), rule: "R14",
                                         confidence: .likely))), .content)
        }
        return (.moment(finish(contentDraft())), .content)
    }

    func firstRule() -> Draft? {
        if let x = r1() { return x }
        if let x = r2() { return x }
        if let x = r4() { return x }
        if let x = r5() { return x }
        if let x = r3() { return x }
        if let x = r6() { return x }
        if let x = r18() { return x }
        if let x = r7r8r9() { return x }
        if let x = r11() { return x }
        if let x = r12() { return x }
        if let x = r13() { return x }
        if let x = r14() { return x }
        if let x = r15() { return x }
        return nil
    }

    func laterRule() -> Draft? {
        if let x = r16() { return x }
        if let x = r17() { return x }
        if let x = r10() { return x }
        if let x = r19() { return x }
        return nil
    }

    // MARK: R1 explicit clock time

    func r1() -> Draft? {
        guard let c = t.clock else { return nil }
        let hours: [Int]
        if let mer = c.meridiem {
            hours = [c.hour % 12 + (mer == .pm ? 12 : 0)]
        } else if c.hour >= 13 || c.hour == 0 || c.hour == 12 {
            hours = [c.hour]
        } else if let p = t.partOfDay, p != .morning, p != .lunch {
            hours = [c.hour + 12]
        } else if t.partOfDay == .morning {
            hours = [c.hour]
        } else {
            hours = [c.hour, c.hour + 12]
        }
        if let day = namedDay() {
            // [Check] "Friday at 7" with no am/pm: 7 to 11 read as morning, 1 to 6 as afternoon.
            let h = hours.count == 1 ? hours[0] : (c.hour >= 7 ? c.hour : c.hour + 12)
            return Draft(start: d.at(DayTime(h, c.minute), day), rule: "R1", phrase: .precise, allowQuiet: true)
        }
        // Today if still ahead, else tomorrow. With no am/pm, the soonest reading outside quiet hours.
        var best: Date? = nil
        for offset in 0...1 {
            let day = d.add(days: offset, to: today)
            for h in hours {
                let x = d.at(DayTime(h, c.minute), day)
                if x <= now { continue }
                if hours.count > 1 && isQuiet(x) { continue }
                if let b = best, b <= x { continue }
                best = x
            }
        }
        let start = best ?? d.at(DayTime(hours[0], c.minute), d.add(days: 1, to: today))
        return Draft(start: start, rule: "R1", phrase: .precise, allowQuiet: true)
    }

    /// A day named alongside a clock time: a date, a weekday, tomorrow, today.
    func namedDay() -> Date? {
        if let x = explicitDate() { return x }
        if let wd = t.weekday { return d.next(weekday: wd, from: now) }
        if t.has("tomorrow") { return d.add(days: 1, to: today) }
        if t.namesToday { return today }
        return nil
    }

    // MARK: R2 relative time

    func r2() -> Draft? {
        guard let r = t.relative else { return nil }
        switch r.unit {
        case .minute:
            return Draft(start: roundUp(now.addingTimeInterval(Double(r.amount) * 60)), rule: "R2", phrase: .precise)
        case .hour:
            return Draft(start: roundUp(now.addingTimeInterval(Double(r.amount) * 3600)), rule: "R2", phrase: .precise)
        case .day:
            return Draft(start: d.issue(d.add(days: r.amount, to: today)), rule: "R2")
        case .week:
            return Draft(start: d.issue(d.add(days: 7 * r.amount, to: today)), rule: "R2")
        case .month:
            return Draft(start: d.issue(d.add(.month, r.amount, to: today)), rule: "R2")
        case .year:
            return Draft(start: d.issue(d.add(.year, r.amount, to: today)), rule: "R2")
        }
    }

    // MARK: R3 calendar anchor

    struct EventMatch { var event: CalendarEventInfo; var sure: Bool }

    func matchEvent() -> EventMatch? {
        let candidates = upcoming
        guard !candidates.isEmpty else { return nil }
        var best: (score: Double, event: CalendarEventInfo, sure: Bool)? = nil
        for phrase in t.anchorPhrases {
            let q = PlannerText.query(phrase)
            for e in candidates {
                if let wd = q.weekday, d.weekday(e.start) != wd { continue }
                if let off = q.dayOffset, !d.same(e.start, d.add(days: off, to: today)) { continue }
                let title = PlannerText.tokens(e.title)
                let matched = q.keywords.filter { k in title.contains { PlannerText.wordsMatch(k, $0) } }.count
                var score: Double
                var sure = false
                if !q.keywords.isEmpty && matched == q.keywords.count {
                    score = 3; sure = true
                } else if matched >= 2 && matched * 2 >= q.keywords.count {
                    score = 2
                } else if q.generic && (q.weekday != nil || q.dayOffset != nil) && !isMultiDay(e) {
                    // "Thursday's meeting": the event on that day.
                    score = matched > 0 ? 1.5 : 1
                } else {
                    continue
                }
                if q.generic && !isMultiDay(e) { score += 0.25 }
                if let b = best, b.score > score || (b.score == score && b.event.start <= e.start) { continue }
                best = (score, e, sure)
            }
        }
        guard let b = best else { return nil }
        return EventMatch(event: b.event, sure: b.sure)
    }

    func r3() -> Draft? {
        var match = matchEvent()
        if match == nil, let id = hints.anchorEventId, let e = upcoming.first(where: { $0.id == id }) {
            match = EventMatch(event: e, sure: false)
        }
        guard let m = match else { return nil }
        let e = m.event
        let confidence: MomentConfidence = m.sure ? .sure : .likely
        if isMultiDay(e) {
            // [Check] Trips: 7 days before; other multi-day or all-day events: 2 days before.
            let lead = isTrip(e) ? 7 : 2
            return Draft(start: d.issue(d.add(days: -lead, to: d.day(e.start))), rule: "R3", confidence: confidence,
                         phrase: .anchor, anchor: e, deadline: e.start)
        }
        var x = placeBefore(e, lead: minutes + 1)
        x.confidence = confidence
        return x
    }

    /// R3 short event: start at event start - lead, in the latest free gap that day long enough.
    func placeBefore(_ e: CalendarEventInfo, lead: Int) -> Draft {
        let eventDay = d.day(e.start)
        let hi = e.start
        let hiCap = min(hi, d.at(Self.quietStart, eventDay))
        let lo = max(now, d.issue(eventDay))
        let need = Double(lead) * 60
        if lo < hiCap {
            let busy = input.events
                .filter { $0.id != e.id && !isMultiDay($0) && $0.start < hiCap && $0.end > lo }
                .map { (max($0.start, lo), min($0.end, hiCap)) }
                .sorted { $0.0 < $1.0 }
            var gaps: [(Date, Date)] = []
            var cursor = lo
            for b in busy {
                if b.0 > cursor { gaps.append((cursor, b.0)) }
                if b.1 > cursor { cursor = b.1 }
            }
            if cursor < hiCap { gaps.append((cursor, hiCap)) }
            if let g = gaps.last(where: { $0.1.timeIntervalSince($0.0) >= need }) {
                return Draft(start: g.1.addingTimeInterval(-need), rule: "R3", phrase: .live, liveUntil: hi, anchor: e)
            }
        }
        let issue = d.issue(eventDay)
        if issue >= now && issue < hi {
            return Draft(start: issue, rule: "R3", phrase: .anchor, anchor: e)
        }
        if d.same(eventDay, now) && now < hi {
            // Too close for a gap: now, until it starts.
            return Draft(start: min(roundUp(now), hi), rule: "R3", phrase: .live, liveUntil: hi, anchor: e)
        }
        // [Check] An event before that day's Issue: the evening before.
        return Draft(start: d.at(Self.tonight, d.add(days: -1, to: eventDay)), rule: "R3", phrase: .anchor,
                     anchor: e, deadline: hi)
    }

    // MARK: R4 flight

    func r4() -> Draft? {
        guard t.hasAny(PlannerText.flightReasonWords) else { return nil }
        guard let f = upcoming.first(where: { isFlight($0) }) else { return nil }
        var start = d.at(Self.tonight, d.add(days: -1, to: d.day(f.start)))
        if start < now {
            start = roundUp(now)
            if isQuiet(start) { start = d.nextIssue(atOrAfter: start) }
        }
        return Draft(start: start, rule: "R4", place: .homeEvening, confidence: .likely, phrase: .flight, anchor: f)
    }

    // MARK: R5 gift

    func r5() -> Draft? {
        guard t.hasGiftWord else { return nil }
        var target: Date? = nil
        var anchor: CalendarEventInfo? = nil
        if let x = explicitDate() {
            target = x
        } else if let h = t.holiday, let x = d.nextHoliday(h, from: now) {
            target = x
        } else if let m = matchEvent() {
            target = d.day(m.event.start); anchor = m.event
        }
        guard let tg = target else { return nil }
        return Draft(start: d.issue(d.add(days: -10, to: tg)), rule: "R5", confidence: .likely,
                     phrase: anchor == nil ? .auto : .anchor, anchor: anchor, deadline: tg)
    }

    // MARK: R6 date

    func explicitDate() -> Date? {
        guard let m = t.dateMatch else { return nil }
        let p = d.ymd(now)
        switch m {
        case .monthDay(let month, let dayOfMonth, let year):
            if let y = year { return d.date(y, month, dayOfMonth) }
            if let x = d.date(p.year, month, dayOfMonth), x >= today { return x }
            return d.date(p.year + 1, month, dayOfMonth)
        case .dayOnly(let dayOfMonth):
            if dayOfMonth >= p.day, let x = d.date(p.year, p.month, dayOfMonth) { return x }
            let y = p.month == 12 ? p.year + 1 : p.year
            let mo = p.month == 12 ? 1 : p.month + 1
            return d.date(y, mo, dayOfMonth)
        }
    }

    func r6() -> Draft? {
        guard let target = explicitDate() else { return nil }
        if t.hasDeadlineWord {
            var start = d.issue(d.add(days: -2, to: target))
            if start < now { start = d.issue(d.add(days: -1, to: target)) }
            return Draft(start: start, rule: "R6", deadline: target)
        }
        return Draft(start: d.issue(target), rule: "R6", deadline: d.add(days: 1, to: target))
    }

    // MARK: R7, R8, R9 day and part of day

    func partTime(_ p: PartOfDay?, _ day: Date) -> Date {
        guard let p else { return d.issue(day) }
        switch p {
        case .morning: return d.issue(day)
        case .lunch: return d.at(Self.lunch, day)
        case .afternoon: return d.at(Self.afternoon, day)
        case .evening: return d.at(Self.tonight, day)
        case .dinner: return d.at(s.homeEveningStart.adding(minutes: 10), day)
        case .bed: return d.at(s.homeEveningEnd, day)
        }
    }

    func place(for p: PartOfDay?) -> MomentPlace {
        switch p {
        case .some(.evening), .some(.dinner), .some(.bed): return .homeEvening
        default: return .any
        }
    }

    func r7r8r9() -> Draft? {
        var part = t.partOfDay
        // "Show the kids Friday": home words with a named day mean dinner that day.
        if part == nil && t.hasHomeWord && (t.weekday != nil || t.has("tomorrow")) { part = .dinner }
        let phrase: Phrase = part == .dinner ? .dinner : .auto
        if let wd = t.weekday {
            // [Check] SPEC: the next one that isn't today; "next Tuesday" on a Wednesday is 6 days out.
            let day = d.next(weekday: wd, from: now)
            return Draft(start: partTime(part, day), rule: "R7", place: place(for: part), phrase: phrase)
        }
        if t.has("tomorrow") {
            let day = d.add(days: 1, to: today)
            return Draft(start: partTime(part, day), rule: "R9", place: place(for: part), phrase: phrase)
        }
        guard t.namesToday || (part != nil && part != .dinner) else { return nil }
        guard let p = part else { return Draft(start: todayFallback(), rule: "R8") }
        let x = partTime(p, today)
        if x > now { return Draft(start: x, rule: "R8", place: place(for: p), phrase: phrase) }
        return Draft(start: partTime(p, d.add(days: 1, to: today)), rule: "R8", place: place(for: p), phrase: phrase)
    }

    // MARK: R10 home

    func r10() -> Draft? {
        guard t.hasHomeWord else { return nil }
        let cutoff = d.at(s.homeEveningStart.adding(minutes: -30), today)
        let day = now < cutoff ? today : d.add(days: 1, to: today)
        let dinnerWords = t.hasAny(["dinner", "supper"])
        return Draft(start: d.at(s.homeEveningStart.adding(minutes: 10), day), rule: "R10", place: .homeEvening,
                     confidence: .likely, phrase: dinnerWords ? .dinner : .auto)
    }

    // MARK: R11 this weekend

    func r11() -> Draft? {
        guard t.has("weekend"), !t.has("next weekend") else { return nil }
        return thisWeekend()
    }

    func thisWeekend() -> Draft {
        let wd = d.weekday(now)
        let noon = d.at(DayTime(12, 0), today)
        let tomorrow = d.add(days: 1, to: today)
        let slot = isWatch ? Self.weekendEvening : s.weekendMorning
        func make(_ start: Date) -> Draft { Draft(start: start, rule: "R11", place: .weekend) }
        switch wd {
        case 7: // Saturday
            if isWatch {
                let x = d.at(Self.weekendEvening, today)
                return make(x > now ? x : d.at(Self.weekendEvening, tomorrow))
            }
            if now < noon { return make(d.at(Self.saturdayAfternoon, today)) }
            return make(d.at(s.weekendMorning, tomorrow))
        case 1: // Sunday
            if now < noon {
                if isWatch { return make(d.at(Self.weekendEvening, today)) }
                let x = d.at(s.weekendMorning, today)
                // [Check] Sunday morning after 9: this afternoon at 2.
                return make(x > now ? x : d.at(Self.saturdayAfternoon, today))
            }
            return make(d.at(slot, d.add(days: 6, to: today)))
        default:
            let sat = d.next(weekday: 7, from: now)
            if hints.needsDayAhead && !isWatch {
                return make(d.at(s.weekendIssue.adding(minutes: 5), sat))
            }
            return make(d.at(slot, sat))
        }
    }

    // MARK: R12 next weekend

    func r12() -> Draft? {
        guard t.has("next weekend") else { return nil }
        let wd = d.weekday(now)
        let coming: Date
        if wd == 7 { coming = today } else if wd == 1 { coming = d.add(days: -1, to: today) } else { coming = d.next(weekday: 7, from: now) }
        let sat = d.add(days: 7, to: coming)
        let sun = d.add(days: 1, to: sat)
        let slot = isWatch ? Self.weekendEvening : s.weekendMorning
        let satBlocked = blocked(sat), sunBlocked = blocked(sun)
        if satBlocked && sunBlocked {
            return Draft(start: d.at(Self.tonight, d.add(days: -1, to: sat)), rule: "R12", place: .homeEvening,
                         confidence: .likely)
        }
        if satBlocked {
            // [Check] Only Saturday blocked: Sunday instead of the Friday before.
            return Draft(start: d.at(slot, sun), rule: "R12", place: .weekend, confidence: .likely)
        }
        return Draft(start: d.at(slot, sat), rule: "R12", place: .weekend)
    }

    func blocked(_ day: Date) -> Bool {
        let ds = d.day(day), de = d.add(days: 1, to: ds)
        return input.events.contains { ($0.isAllDay || isMultiDay($0)) && $0.start < de && $0.end > ds }
    }

    // MARK: R13 next week

    func r13() -> Draft? {
        if t.has("next week") {
            return Draft(start: d.issue(d.next(weekday: 2, from: now)), rule: "R13")
        }
        if t.has("this week") {
            // [Check] Not in SPEC: "this week" is the lightest workday Issue from tomorrow to Friday,
            // or this weekend when the week is over.
            var days: [Date] = []
            var x = d.add(days: 1, to: today)
            while d.weekday(x) != 7 && d.weekday(x) != 1 {
                if d.isWorkday(x) { days.append(x) }
                x = d.add(days: 1, to: x)
            }
            if let best = lightest(days) { return Draft(start: d.issue(best), rule: "R13") }
            var w = thisWeekend(); w.rule = "R13"
            return w
        }
        return nil
    }

    // MARK: R14 month

    func r14() -> Draft? {
        guard let m = t.monthSpec else { return nil }
        return Draft(start: monthStart(m.which, part: m.part, forceNext: m.forceNext), rule: "R14")
    }

    func monthStart(_ which: MonthWhich, part: MonthPart, forceNext: Bool) -> Date {
        let p = d.ymd(now)
        var y = p.year, m = p.month
        switch which {
        case .thisMonth: break
        case .nextMonth:
            m += 1
            if m > 12 { m = 1; y += 1 }
        case .named(let n):
            m = n
            if n < p.month || (n == p.month && forceNext) { y += 1 }
        }
        let current = y == p.year && m == p.month
        switch part {
        case .end:
            return d.issue(d.lastWorkday(year: y, month: m))
        case .mid:
            if let fifteen = d.date(y, m, 15) {
                let x = d.issue(d.firstWorkday(onOrAfter: fifteen))
                if x >= now || !current { return x }
            }
            return thisMonthSoon()
        case .start:
            if !current, let first = d.date(y, m, 1) { return d.issue(d.firstWorkday(onOrAfter: first)) }
            return thisMonthSoon()
        }
    }

    /// [Check] "This month" when its first weekday has passed: the lightest workday 2 to 5 days out
    /// that is still in this month, else its last workday, else the next Issue.
    func thisMonthSoon() -> Date {
        let month = d.ymd(now).month
        let days = (2...5).map { d.add(days: $0, to: today) }.filter { d.ymd($0).month == month && d.isWorkday($0) }
        if let best = lightest(days) { return d.issue(best) }
        let p = d.ymd(now)
        let last = d.issue(d.lastWorkday(year: p.year, month: p.month))
        return last >= now ? last : d.nextIssue(atOrAfter: now)
    }

    // MARK: R15 seasons

    func r15() -> Draft? {
        guard let spec = t.season else { return nil }
        if d.season(of: now) == spec.season && !spec.next {
            var x = thisWeekend(); x.rule = "R15"
            return x
        }
        if let best = hints.bestDate, best > now {
            // The relay's best date (peak color): the Saturday of that weekend.
            let bd = d.day(best)
            let sat = d.weekday(bd) == 1 ? d.add(days: -1, to: bd) : d.saturday(onOrAfter: bd)
            var start = d.at(s.weekendMorning, sat)
            if start < now { start = d.at(s.weekendMorning, d.saturday(onOrAfter: bd)) }
            return Draft(start: start, rule: "R15", place: .weekend, confidence: .likely)
        }
        let st = d.nextStart(of: spec.season, after: now)
        return Draft(start: d.at(s.weekendMorning, d.saturday(onOrAfter: st)), rule: "R15", place: .weekend)
    }

    // MARK: R16 holidays

    func r16() -> Draft? {
        guard let h = t.holiday, let target = d.nextHoliday(h, from: now) else { return nil }
        let lead = t.hasLeadWord
        var start: Date
        if lead {
            // [Check] "for Thanksgiving" counts as "before": a recipe on the day is too late to shop for.
            let words = Set(t.toks).union(PlannerText.tokens(input.title))
            let days = words.isDisjoint(with: PlannerText.giftOrTravelWords) ? 2 : 14
            start = d.issue(d.add(days: -days, to: target))
        } else {
            start = d.issue(target)
        }
        var place: MomentPlace = .any
        // [Check] Judgment from example 27: if the holiday falls inside a trip on the calendar and the
        // moment would land during it, the last weekend morning before the trip leaves.
        if let trip = input.events.first(where: { isTrip($0) && isMultiDay($0) && $0.start <= target && $0.end > target }),
           start >= trip.start {
            var sat = d.add(days: -1, to: d.day(trip.start))
            var guardCount = 0
            while d.weekday(sat) != 7 && guardCount < 7 { sat = d.add(days: -1, to: sat); guardCount += 1 }
            start = d.at(s.weekendMorning, sat)
            place = .weekend
        }
        return Draft(start: start, rule: "R16", place: place, confidence: .likely,
                     deadline: lead ? target : d.add(days: 1, to: target))
    }

    // MARK: R17 next quarter, next year

    func r17() -> Draft? {
        let p = d.ymd(now)
        if t.has("next quarter") {
            var m = ((p.month - 1) / 3) * 3 + 4
            var y = p.year
            if m > 12 { m -= 12; y += 1 }
            guard let first = d.date(y, m, 1) else { return nil }
            return Draft(start: d.issue(d.firstWorkday(onOrAfter: first)), rule: "R17")
        }
        if t.has("next year") {
            guard let first = d.date(p.year + 1, 1, 1) else { return nil }
            return Draft(start: d.issue(d.firstWorkday(onOrAfter: first)), rule: "R17")
        }
        if t.hasAny(["end of the year", "end of year", "end of this year", "year end"]) {
            let x = d.issue(d.lastWorkday(year: p.year, month: 12))
            return Draft(start: x >= now ? x : d.issue(d.lastWorkday(year: p.year + 1, month: 12)), rule: "R17")
        }
        return nil
    }

    // MARK: R18 work

    func r18() -> Draft? {
        guard t.hasWorkWord else { return nil }
        let workAt = s.workStart.adding(minutes: 30)
        var day: Date
        if let wd = t.weekday { day = d.next(weekday: wd, from: now) }
        else if t.has("tomorrow") { day = d.add(days: 1, to: today) }
        else { day = d.at(workAt, today) > now ? today : d.add(days: 1, to: today) }
        var count = 0
        while (!d.isWorkday(day) || isAway(day)) && count < 30 {
            day = d.add(days: 1, to: day); count += 1
        }
        return Draft(start: d.at(workAt, day), rule: "R18", place: .work, confidence: .likely)
    }

    // MARK: R19 places

    func r19() -> Draft? {
        guard t.hasPlaceWord else { return nil }
        let todayErrand = d.at(Self.errand, today)
        let day = (d.weekday(now) == 7 && todayErrand > now) ? today : d.next(weekday: 7, from: now)
        return Draft(start: d.at(Self.errand, day), rule: "R19", confidence: .likely, phrase: .errand)
    }

    // MARK: R20 content, R21 ask

    func somedayDraft() -> Draft {
        let sat = d.saturday(onOrAfter: d.add(days: 28, to: today))
        return Draft(start: d.at(s.weekendIssue, sat), rule: "R20", place: .weekend, confidence: .likely)
    }

    func contentDraft() -> Draft {
        let mins = minutes
        if hints.weekendProject || mins > 45 {
            return Draft(start: weekendSlot(s.weekendMorning), rule: "R20", place: .weekend, confidence: .likely)
        }
        if isWatch && mins >= 15 {
            return Draft(start: weekendSlot(Self.weekendEvening), rule: "R20", place: .weekend, confidence: .likely)
        }
        if mins >= 15 {
            return Draft(start: weekendSlot(s.weekendMorning), rule: "R20", place: .weekend, confidence: .likely)
        }
        // [Check] Under 15 minutes (short videos included): an Issue 2 to 5 days out, the lightest.
        let days = (2...5).map { d.add(days: $0, to: today) }
        let day = lightest(days) ?? d.add(days: 2, to: today)
        return Draft(start: d.issue(day), rule: "R20", confidence: .likely)
    }

    func r21() -> PlanOutcome {
        var fb: Draft
        var choices = ["This weekend", "Next month", "Pick a date"]
        if let m = hints.monthHint, (1...12).contains(m) {
            fb = Draft(start: monthStart(.named(m), part: .start, forceNext: false), rule: "R21")
            let next = d.ymd(now).month % 12 + 1
            if m != next { choices[1] = "In " + PlannerEngine.monthNames[m - 1] }
        } else {
            fb = contentDraft()
            fb.rule = "R21"
        }
        fb.confidence = .guess
        return .ask(choices: choices, fallback: finish(fb))
    }

    /// The weekend day (this coming weekend) at that time with the fewest moments planned.
    func weekendSlot(_ time: DayTime) -> Date {
        var days: [Date] = []
        for offset in 0..<14 {
            let day = d.add(days: offset, to: today)
            guard d.isWeekend(day), d.at(time, day) > now else { continue }
            days.append(day)
            if d.weekday(day) == 1 || days.count == 2 { break }
        }
        let chosen = lightest(days) ?? d.next(weekday: 7, from: now)
        return d.at(time, chosen)
    }

    func plannedCount(_ day: Date) -> Int { input.plannedPerDay[d.day(day)] ?? 0 }

    /// Fewest moments planned, preferring days with room in the daily budget; ties go to the earliest.
    func lightest(_ days: [Date]) -> Date? {
        guard !days.isEmpty else { return nil }
        let withRoom = days.filter { plannedCount($0) < Self.dailyBudget }
        let pool = withRoom.isEmpty ? days : withRoom
        var best = pool[0]
        for x in pool.dropFirst() where plannedCount(x) < plannedCount(best) { best = x }
        return best
    }

    // MARK: Later

    func later(_ choice: LaterChoice) -> PlannedMoment {
        switch choice {
        case .tonight:
            let a = d.at(Self.tonight, today)
            if a > now { return finish(Draft(start: a, rule: "R8", place: .homeEvening)) }
            let b = d.at(s.homeEveningEnd, today)
            if b > now { return finish(Draft(start: b, rule: "R8", place: .homeEvening)) }
            return finish(Draft(start: d.at(Self.tonight, d.add(days: 1, to: today)), rule: "R9", place: .homeEvening))
        case .tomorrowMorning:
            return finish(Draft(start: d.issue(d.add(days: 1, to: today)), rule: "R9"))
        case .thisWeekend:
            return finish(thisWeekend())
        case .nextWeek:
            return finish(Draft(start: d.issue(d.next(weekday: 2, from: now)), rule: "R13"))
        case .youChoose:
            return finish(contentDraft())
        }
    }

    // MARK: Event kinds

    func isMultiDay(_ e: CalendarEventInfo) -> Bool {
        e.isAllDay || e.end.timeIntervalSince(e.start) >= 20 * 3600
    }

    func isTrip(_ e: CalendarEventInfo) -> Bool {
        !Set(PlannerText.tokens(e.title)).isDisjoint(with: PlannerText.tripWords)
    }

    func isFlight(_ e: CalendarEventInfo) -> Bool {
        !Set(PlannerText.tokens(e.title)).isDisjoint(with: PlannerText.flightTitleWords)
    }

    /// A day the calendar shows as away: inside a multi-day trip.
    func isAway(_ day: Date) -> Bool {
        let ds = d.day(day), de = d.add(days: 1, to: ds)
        return input.events.contains { isMultiDay($0) && isTrip($0) && $0.start < de && $0.end > ds }
    }

    // MARK: Guards

    func isQuiet(_ x: Date) -> Bool {
        let m = d.time(x).totalMinutes
        return m >= Self.quietStart.totalMinutes || m < d.issueTime(x).totalMinutes
    }

    func roundUp(_ x: Date) -> Date {
        let r = (x.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
        return Date(timeIntervalSinceReferenceDate: r)
    }

    /// Today's next useful time: the Issue, 3:30 PM or 7:30 PM if still ahead, else the next Issue.
    func todayFallback() -> Date {
        for time in [d.issueTime(today), Self.afternoon, Self.tonight] {
            let x = d.at(time, today)
            if x >= now { return x }
        }
        return d.nextIssue(atOrAfter: now)
    }

    func finish(_ draft: Draft) -> PlannedMoment {
        var x = draft
        var moved = false
        if x.liveUntil == nil {
            // Never in the past.
            if x.start < now {
                let next = d.nextIssue(atOrAfter: now)
                if let deadline = x.deadline, next >= deadline { x.start = todayFallback() } else { x.start = next }
                moved = true
            }
            // Never in quiet hours, except a time you set yourself (R1).
            if !x.allowQuiet && isQuiet(x.start) {
                x.start = d.nextIssue(atOrAfter: x.start)
                moved = true
            }
            // Never more than 18 months out.
            let cap = d.add(.month, 18, to: now)
            if x.start > cap {
                var day = d.day(cap)
                if d.issue(day) > cap { day = d.add(days: -1, to: day) }
                x.start = d.issue(day)
                moved = true
            }
        }
        if moved {
            if x.phrase != .anchor { x.phrase = .auto }
            let m = d.time(x.start).totalMinutes
            if x.place == .homeEvening && (m < s.homeEveningStart.totalMinutes || m > s.homeEveningEnd.totalMinutes) {
                x.place = .any
            }
        }

        let day = d.day(x.start)
        let surface: MomentSurface
        let end: Date
        if let until = x.liveUntil {
            surface = .liveActivity
            end = until
        } else if x.start == d.issue(day) {
            surface = .issue
            end = d.at(Self.lastMinute, day)
        } else {
            surface = .notification
            let nine = d.at(Self.quietStart, day)
            let plus3 = x.start.addingTimeInterval(3 * 3600)
            if x.start < nine {
                end = min(plus3, nine)
            } else {
                end = max(min(plus3, d.at(Self.lastMinute, day)), x.start.addingTimeInterval(60))
            }
        }
        return PlannedMoment(start: x.start, end: end, surface: surface, place: x.place, ruleId: x.rule,
                             confidence: x.confidence, explanation: explain(x, surface: surface),
                             laterLabel: laterLabel(x, surface: surface), anchorEventId: x.anchor?.id)
    }

    // MARK: Words for the capture line (SPEC 4.7)

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    func dayName(_ x: Date) -> String { Self.weekdayNames[(d.weekday(x) + 6) % 7] }

    func farDate(_ x: Date) -> String {
        let p = d.ymd(x)
        var out = "\(Self.weekdayShort[(d.weekday(x) + 6) % 7]), \(Self.monthShort[(p.month + 11) % 12]) \(p.day)"
        if p.year != d.ymd(now).year { out += ", \(p.year)" }
        return out
    }

    func clockText(_ x: Date, meridiem: Bool) -> String {
        let tm = d.time(x)
        let h12 = tm.hour % 12 == 0 ? 12 : tm.hour % 12
        let mm = tm.minute < 10 ? "0\(tm.minute)" : "\(tm.minute)"
        return meridiem ? "\(h12):\(mm) \(tm.hour < 12 ? "AM" : "PM")" : "\(h12):\(mm)"
    }

    /// "this morning", "tonight", "tomorrow at lunch", "Saturday morning", "Sat, Nov 21".
    func when(_ x: Date) -> String {
        let diff = d.daysBetween(now, x)
        let h = d.time(x).hour
        let part = h < 12 ? "morning" : (h < 14 ? "lunch" : (h < 17 ? "afternoon" : "evening"))
        switch diff {
        case 0:
            return h < 12 ? "this morning" : (h < 14 ? "at lunch today" : (h < 17 ? "this afternoon" : "tonight"))
        case 1:
            return part == "lunch" ? "tomorrow at lunch" : "tomorrow \(part)"
        case 2...6:
            return part == "lunch" ? "\(dayName(x)) at lunch" : "\(dayName(x)) \(part)"
        default:
            return farDate(x)
        }
    }

    func explain(_ x: Draft, surface: MomentSurface) -> String {
        let diff = d.daysBetween(now, x.start)
        let line: String
        switch x.phrase {
        case .live:
            let title = x.anchor?.title ?? "your event"
            line = "Back at \(clockText(x.start, meridiem: false)), before \(title)"
        case .dinner:
            let dayWord: String
            switch diff {
            case 0: dayWord = "tonight"
            case 1: dayWord = "tomorrow"
            case 2...6: dayWord = dayName(x.start)
            default: dayWord = "on " + farDate(x.start)
            }
            line = "Back at dinner \(dayWord)"
        case .errand:
            line = "Comes back \(when(x.start)) (I don't use your location)"
        case .flight:
            line = "Back \(when(x.start)), before your flight"
        case .precise:
            let c = clockText(x.start, meridiem: true)
            switch diff {
            case 0: line = "Back at \(c) " + (d.time(x.start).hour >= 17 ? "tonight" : "today")
            case 1: line = "Back tomorrow at \(c)"
            case 2...6: line = "Back \(dayName(x.start)) at \(c)"
            default: line = "Back \(farDate(x.start)) at \(c)"
            }
        case .anchor:
            line = "Comes back \(when(x.start)), before \(x.anchor?.title ?? "your event")"
        case .auto:
            var l = "Comes back \(when(x.start))"
            if x.place == .work { l += ", at work" }
            if x.place == .homeEvening && surface != .issue { l += ", at home" }
            line = l
        }
        return line.count <= 60 ? line : String(line.prefix(59)) + "\u{2026}"
    }

    func laterLabel(_ x: Draft, surface: MomentSurface) -> String {
        if surface == .liveActivity {
            if let a = x.anchor, let last = PlannerText.tokens(a.title).last {
                let label = "After " + last
                if label.count <= 18 { return label }
            }
            return "After the event"
        }
        if d.time(x.start).hour < 17 { return "Tonight" }
        return d.weekday(x.start) == 6 ? "Saturday" : "Tomorrow"
    }
}

enum Phrase: Sendable, Equatable { case auto, live, anchor, dinner, errand, flight, precise }

/// A moment before the guards (past, quiet hours, 18 months) and the words are applied.
struct Draft {
    var start: Date
    var rule: String
    var place: MomentPlace
    var confidence: MomentConfidence
    var phrase: Phrase
    var liveUntil: Date?
    var anchor: CalendarEventInfo?
    var allowQuiet: Bool
    /// The moment must arrive before this; past-time repair falls back to today when the next Issue is too late.
    var deadline: Date?

    init(start: Date, rule: String, place: MomentPlace = .any, confidence: MomentConfidence = .sure,
         phrase: Phrase = .auto, liveUntil: Date? = nil, anchor: CalendarEventInfo? = nil,
         allowQuiet: Bool = false, deadline: Date? = nil) {
        self.start = start; self.rule = rule; self.place = place; self.confidence = confidence
        self.phrase = phrase; self.liveUntil = liveUntil; self.anchor = anchor
        self.allowQuiet = allowQuiet; self.deadline = deadline
    }
}

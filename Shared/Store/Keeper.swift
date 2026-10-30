import Foundation
import SwiftData
import ShoeboxCore

/// Opens the one store in the App Group. If it can't be opened, Shoebox never replaces it:
/// it runs on an empty in-memory store and says so, so nothing on disk is overwritten.
@MainActor
enum StoreBox {
    static let shared: (container: ModelContainer, failed: Bool) = open()

    static var container: ModelContainer { shared.container }

    /// Screenshot runs in CI: an in-memory store with sample saves; the real store is never opened.
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    private static func open() -> (ModelContainer, Bool) {
        if demo { return (memory(), false) }
        let schema = Schema(ShoeboxSchema.models)
        // In the App Group when it exists (every signed build); otherwise in this app's own folder, so an
        // unsigned test build never crashes. SwiftData's groupContainer option is fatal without the entitlement.
        let config = ModelConfiguration("Shoebox", schema: schema, url: AppGroup.container.appending(path: "Shoebox.store"))
        if let c = try? ModelContainer(for: schema, configurations: config) { return (c, false) }
        return (memory(), true)
    }

    static func memory() -> ModelContainer {
        let schema = Schema(ShoeboxSchema.models)
        let config = ModelConfiguration("Memory", schema: schema, isStoredInMemoryOnly: true)
        do { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("Shoebox couldn't make even an in-memory store: \(error)") }
    }
}

/// Everything that changes a save goes through here, so every change is stamped, logged and planned the same way.
@MainActor
final class Keeper {
    let context: ModelContext
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    init(context: ModelContext) { self.context = context }

    static func shared() -> Keeper { Keeper(context: StoreBox.container.mainContext) }

    // MARK: Reading

    func allSaves(includeDeleted: Bool = false) -> [Save] {
        let d = FetchDescriptor<Save>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(d)) ?? []
        return includeDeleted ? all : all.filter { $0.deletedAt == nil }
    }

    func save(id: UUID) -> Save? {
        var d = FetchDescriptor<Save>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func moment(id: UUID) -> Moment? {
        var d = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func nextMoment(for save: Save) -> Moment? { save.nextMomentId.flatMap(moment(id:)) }

    func openMoments() -> [Moment] {
        let scheduled = MomentState.scheduled.rawValue, delivered = MomentState.delivered.rawValue
        let d = FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil && ($0.stateRaw == scheduled || $0.stateRaw == delivered) },
                                        sortBy: [SortDescriptor(\.start)])
        return (try? context.fetch(d)) ?? []
    }

    func attachments(for save: Save) -> [Attachment] {
        let sid = save.id
        let d = FetchDescriptor<Attachment>(predicate: #Predicate { $0.saveId == sid && $0.deletedAt == nil })
        return (try? context.fetch(d)) ?? []
    }

    func picture(for save: Save) -> URL? {
        let list = attachments(for: save)
        let pick = list.first { $0.role == .thumbnail } ?? list.first { $0.role == .picture } ?? list.first { $0.role == .original && $0.mime.hasPrefix("image/") }
        return pick?.fileURL
    }

    func events(for save: Save) -> [MomentEvent] {
        let sid = save.id
        let d = FetchDescriptor<MomentEvent>(predicate: #Predicate { $0.saveId == sid }, sortBy: [SortDescriptor(\.at)])
        return (try? context.fetch(d)) ?? []
    }

    /// Search across your words first, then the saved thing. Quiet and let-go saves are found too.
    func search(_ query: String) -> [Save] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allSaves() }
        let words = q.split(separator: " ").map(String.init)
        func score(_ s: Save) -> Int {
            var total = 0
            for w in words {
                if s.reason.lowercased().contains(w) { total += 4 }
                if s.title.lowercased().contains(w) { total += 3 }
                if s.tags.contains(where: { $0.contains(w) }) { total += 2 }
                if (s.text ?? "").lowercased().contains(w) || s.summary.lowercased().contains(w) || s.transcript.lowercased().contains(w) { total += 1 }
                if (s.host ?? "").contains(w) || (s.author ?? "").lowercased().contains(w) { total += 1 }
            }
            return total
        }
        return allSaves().map { ($0, score($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    // MARK: Keeping

    /// Keeps something. Never blocks for a reason; plans its one moment at once.
    @discardableResult
    func keep(_ draft: Detection.Draft, reason: String, reasonSource: ReasonSource, source: SaveSource,
              files: [(data: Data, mime: String, name: String?)] = [], events: [CalendarEventInfo] = []) -> (Save, PlanOutcome) {
        let t = now()
        var v = SaveValue(now: t, kind: draft.kind, title: draft.title, reason: SpokenReason.clip(reason.trimmingCharacters(in: .whitespacesAndNewlines)),
                          reasonSource: reason.isEmpty ? .none : reasonSource, source: source, status: .unplanned)
        v.text = draft.text; v.url = draft.url.map(Detection.unwrapLink); v.author = draft.author
        v.videoId = draft.videoId; v.imageURL = draft.imageURL
        v.minutes = Minutes.estimate(kind: draft.kind, text: draft.text, isBook: false)
        let save = Save(v)
        context.insert(save)
        for f in files { addFile(f.data, mime: f.mime, name: f.name, to: save, role: .original) }
        log(save, .saved, detail: source.rawValue)
        let outcome = plan(save, events: events)
        try? context.save()
        return (save, outcome)
    }

    @discardableResult
    func addFile(_ data: Data, mime: String, name: String?, to save: Save, role: AttachmentRole) -> Attachment? {
        let id = UUID()
        let ext = name.flatMap { $0.contains(".") ? $0.split(separator: ".").last.map(String.init) : nil }?.lowercased()
            ?? (mime == "application/pdf" ? "pdf" : mime == "image/png" ? "png" : mime.hasPrefix("image/") ? "jpg" : "bin")
        let fileName = "Files/\(id.uuidString.lowercased()).\(ext)"
        do { try data.write(to: AppGroup.url(forStored: fileName), options: .atomic) } catch { return nil }
        let a = Attachment(AttachmentValue(id: id, saveId: save.id, role: role, fileName: fileName, mime: mime, size: data.count,
                                           sha256: FileHash.sha256(data), createdAt: now()))
        context.insert(a)
        return a
    }

    // MARK: Planning

    func input(for save: Save, events: [CalendarEventInfo]) -> PlanInput {
        var load: [Date: Int] = [:]
        for m in openMoments() { load[calendar.startOfDay(for: m.start), default: 0] += 1 }
        return PlanInput(reason: save.reason, kind: save.kind, minutes: save.minutes, intent: save.intent, title: save.title,
                         now: now(), events: events, plannedPerDay: load, hints: nil)
    }

    /// Plans (or re-plans) the one moment for a save, replacing any open one.
    @discardableResult
    func plan(_ save: Save, events: [CalendarEventInfo], hints: ModelHints? = nil, reasonText: String? = nil) -> PlanOutcome {
        if save.dueDate != nil {
            if let p = step(save, after: now(), isNew: nextMoment(for: save) == nil && save.passes == 0 && save.laters == 0) {
                setMoment(p, on: save)
                return .moment(p)
            }
            // Its date has passed with no answer: quiet, not done (SPEC 7.5).
            closeMoment(of: save, as: .cancelled)
            save.status = .quiet; save.quietAt = now(); save.inboxAt = nil
            log(save, .quiet, detail: "date passed")
            return .moment(PlannedMoment(start: now(), end: now(), surface: .issue, place: .any, ruleId: "step-none", confidence: .sure,
                                         explanation: "Its date has passed", laterLabel: "Tomorrow"))
        }
        var inp = input(for: save, events: events)
        inp.hints = hints
        if let reasonText { inp.reason = reasonText }
        let outcome = ReturnPlanner.plan(inp, settings: Prefs.load().plannerSettings, calendar: calendar)
        setMoment(budgeted(outcome.moment, for: save), on: save)
        return outcome
    }

    /// SPEC 7.6: the next dated step after a time.
    func step(_ save: Save, after t: Date, isNew: Bool = false) -> PlannedMoment? {
        guard let due = save.dueDate,
              var p = DatedSteps.next(target: due, kind: save.dueKind, now: t, isNew: isNew, settings: Prefs.load().plannerSettings, calendar: calendar)
        else { return nil }
        // Name the actual time: "Back Tuesday morning, 5 days before".
        let when = p.surface == .issue ? Phrases.day(p.start, now: now(), calendar: calendar) + " morning"
                                       : Phrases.day(p.start, now: now(), calendar: calendar) + " evening"
        let why = switch p.ruleId { case "step-5": ", 5 days before"; case "step-eve": ", the evening before"; case "step-0": ", the day of"; default: "" }
        p.explanation = String(("Back " + when.replacingOccurrences(of: "Today morning", with: "this morning")
                                .replacingOccurrences(of: "Today evening", with: "this evening") + why).prefix(60))
        return p
    }

    /// Kept from the inbox: it stays planned, just out of the inbox.
    func keepFromInbox(_ save: Save) {
        save.inboxAt = nil; save.touch(now())
        log(save, .edited, detail: "kept from inbox")
        try? context.save()
    }

    /// SPEC 4.6: at most 4 a day, timed ones 2 hours apart; calendar-tied moments always win.
    func budgeted(_ p: PlannedMoment, for save: Save) -> PlannedMoment {
        let prefs = Prefs.load()
        let issueOn: (Date) -> Date = { d in
            DailyIssue.time(on: d, weekday: (prefs.weekdayIssue.hour, prefs.weekdayIssue.minute),
                            weekend: (prefs.weekendIssue.hour, prefs.weekendIssue.minute), calendar: self.calendar)
        }
        var existing: [DailyBudget.Slot] = []
        var issueDays = Set<Date>()
        for m in openMoments() where m.saveId != save.id {
            if m.surface == .issue { issueDays.insert(calendar.startOfDay(for: m.start)); continue }
            existing.append(.init(start: m.start, anchored: m.anchorEventId != nil, surface: m.surface))
        }
        for d in issueDays { existing.append(.init(start: issueOn(d), anchored: false, surface: .issue)) }
        let candidate = DailyBudget.Slot(start: p.start, anchored: p.anchorEventId != nil, surface: p.surface)
        let issueToday = issueOn(p.start)
        var out = p
        switch DailyBudget.place(candidate, existing: existing, issueTime: issueToday, now: now(), calendar: calendar, issueOn: issueOn) {
        case .keep: return p
        case .joinIssue:
            out.start = issueToday
            out.surface = .issue
        case .move(let t):
            out.start = t
            if t == issueOn(t) { out.surface = .issue }
        }
        out.end = out.surface == .issue
            ? (calendar.date(bySettingHour: 23, minute: 59, second: 0, of: out.start) ?? out.start)
            : QuietRule.windowEnd(surface: out.surface, deliveredAt: out.start, anchorStart: nil, calendar: calendar)
        out.explanation = "Comes back " + Phrases.when(out.start, now: now(), calendar: calendar)
        return out
    }

    /// SPEC 4.5: after 10 answered home-evening moments, the window follows when you actually answer.
    func learnHome(from m: Moment?) {
        guard let m, m.place == .homeEvening else { return }
        let c = calendar.dateComponents([.hour, .minute], from: now())
        let minute = (c.hour ?? 18) * 60 + (c.minute ?? 0)
        Prefs.update { p in
            p.homeAnswers = Array((p.homeAnswers + [minute]).suffix(20))
            guard p.homeAnswers.count >= 10 else { return }
            let sorted = p.homeAnswers.sorted()
            let median = sorted[sorted.count / 2]
            let start = p.homeEveningStart.hour * 60 + p.homeEveningStart.minute
            let length = (p.homeEveningEnd.hour * 60 + p.homeEveningEnd.minute) - start
            guard abs(median - start) > 30 else { return }
            let newStart = min(21 * 60, max(16 * 60 + 30, median))
            let newEnd = min(23 * 60, newStart + max(60, length))
            p.homeEveningStart = .init(hour: newStart / 60, minute: newStart % 60)
            p.homeEveningEnd = .init(hour: newEnd / 60, minute: newEnd % 60)
            p.homeAnswers = []
        }
    }

    func setMoment(_ p: PlannedMoment, on save: Save) {
        if let old = nextMoment(for: save), old.state == .scheduled || old.state == .delivered { old.state = .cancelled; old.updatedAt = now() }
        let m = Moment(MomentValue(id: UUID(), saveId: save.id, start: p.start, end: p.end, surface: p.surface, place: p.place,
                                   ruleId: p.ruleId, confidence: p.confidence, explanation: p.explanation, laterLabel: p.laterLabel,
                                   state: .scheduled, createdAt: now()), anchorEventId: p.anchorEventId)
        context.insert(m)
        save.nextMomentId = m.id
        save.status = .planned
        save.touch(now())
        log(save, .planned, moment: m, detail: p.ruleId)
    }

    // MARK: Verdicts (SPEC 3)

    func done(_ save: Save, surface: String? = nil) {
        let m = closeMoment(of: save, as: .answered)
        learnHome(from: m)
        save.status = .done; save.doneAt = now(); save.nextMomentId = nil; save.inboxAt = nil; save.touch(now())
        log(save, .done, moment: m, surface: surface)
        try? context.save()
    }

    func drop(_ save: Save, surface: String? = nil) {
        let m = closeMoment(of: save, as: .answered)
        save.status = .dropped; save.droppedAt = now(); save.nextMomentId = nil; save.inboxAt = nil; save.touch(now())
        log(save, .dropped, moment: m, surface: surface)
        try? context.save()
    }

    /// Later never counts as a pass. Returns the new moment.
    @discardableResult
    func later(_ save: Save, _ choice: LaterChoice, events: [CalendarEventInfo], surface: String? = nil) -> PlannedMoment {
        let m = closeMoment(of: save, as: .answered)
        save.laters += 1
        save.inboxAt = nil
        log(save, .later, moment: m, surface: surface, detail: choice.rawValue)
        // A dated post's Later is its next step (SPEC 7.6).
        if choice == .youChoose, save.dueDate != nil, let p = step(save, after: max(now(), m?.start ?? now())) {
            setMoment(p, on: save)
            try? context.save()
            return p
        }
        let p = ReturnPlanner.later(choice, input: input(for: save, events: events), settings: Prefs.load().plannerSettings, calendar: calendar)
        setMoment(p, on: save)
        try? context.save()
        return p
    }

    /// A time you picked yourself.
    func later(_ save: Save, at date: Date, surface: String? = nil) {
        let m = closeMoment(of: save, as: .answered)
        save.laters += 1
        log(save, .later, moment: m, surface: surface, detail: "you")
        let p = PlannedMoment(start: date, end: date.addingTimeInterval(3 * 3600), surface: .notification, place: .any, ruleId: "you",
                              confidence: .sure, explanation: "Comes back " + Phrases.when(date, calendar: calendar),
                              laterLabel: "Tomorrow", anchorEventId: nil)
        setMoment(p, on: save)
        try? context.save()
    }

    /// The window closed without an answer (SPEC 5). Second pass: quiet.
    func pass(_ save: Save, events: [CalendarEventInfo], surface: String? = nil) {
        let m = closeMoment(of: save, as: .passed)
        // Steps before the last one don't count toward quiet (SPEC 7.6).
        if save.dueDate != nil, let p = step(save, after: max(now(), m?.start ?? now())) {
            log(save, .passed, moment: m, surface: surface, detail: "step")
            setMoment(p, on: save)
            save.touch(now())
            try? context.save()
            return
        }
        save.passes += 1
        log(save, .passed, moment: m, surface: surface)
        if QuietRule.afterPass(passes: save.passes, isSchoolInfo: Engine.schoolKind(save) == .info) == .quiet {
            save.status = .quiet; save.quietAt = now(); save.nextMomentId = nil
            log(save, .quiet)
        } else {
            plan(save, events: events)
        }
        save.touch(now())
        try? context.save()
    }

    /// Opened without a verdict: not a pass; re-planned like "You choose".
    func opened(_ save: Save, surface: String? = nil) {
        log(save, .opened, moment: nextMoment(for: save), surface: surface)
        try? context.save()
    }

    /// Bring it back (quiet) or Restore (done, dropped): passes and laters reset, the planner places it.
    func bringBack(_ save: Save, _ choice: LaterChoice, events: [CalendarEventInfo]) {
        let was = save.status
        save.passes = 0; save.laters = 0; save.quietAt = nil; save.doneAt = nil; save.droppedAt = nil
        save.status = .unplanned
        log(save, was == .quiet ? .broughtBack : .restored, detail: was.rawValue)
        let p = ReturnPlanner.later(choice, input: input(for: save, events: events), settings: Prefs.load().plannerSettings, calendar: calendar)
        setMoment(p, on: save)
        try? context.save()
    }

    func editReason(_ save: Save, to text: String, events: [CalendarEventInfo]) {
        save.reason = SpokenReason.clip(text.trimmingCharacters(in: .whitespacesAndNewlines))
        save.reasonSourceRaw = ReasonSource.typed.rawValue
        if !save.editedRaw.contains(EditedField.reason.rawValue) { save.editedRaw.append(EditedField.reason.rawValue) }
        log(save, .edited, detail: "reason")
        if save.status == .planned || save.status == .unplanned { plan(save, events: events) }
        save.touch(now())
        try? context.save()
    }

    // MARK: Delete (only you; bytes removed at once)

    func delete(_ save: Save) {
        if let m = nextMoment(for: save) { m.state = .cancelled }
        for a in attachments(for: save) {
            try? FileManager.default.removeItem(at: a.fileURL)
            a.deletedAt = now(); a.fileName = ""; a.sha256 = ""
        }
        let t = now()
        // Tombstone: everything cleared but the four sync fields.
        save.deletedAt = t; save.updatedAt = t
        save.reason = ""; save.title = ""; save.text = nil; save.url = nil; save.author = nil; save.summary = ""; save.hook = ""
        save.points = []; save.extended = ""; save.transcript = ""; save.tags = []; save.thoughtsJSON = nil; save.schoolJSON = nil
        save.imageURL = nil; save.videoId = nil; save.alt = ""; save.emailFrom = nil; save.emailFromName = nil; save.emailSubject = nil
        save.nextMomentId = nil
        try? context.save()
    }

    func deleteEverything() {
        for s in allSaves() { delete(s) }
        try? FileManager.default.removeItem(at: AppGroup.files)
        try? context.save()
    }

    // MARK: Helpers

    @discardableResult
    private func closeMoment(of save: Save, as state: MomentState) -> Moment? {
        guard let m = nextMoment(for: save) else { return nil }
        if m.state == .scheduled || m.state == .delivered {
            m.state = state
            if state == .answered { m.answeredAt = now() }
            m.updatedAt = now()
        }
        save.nextMomentId = nil
        return m
    }

    func log(_ save: Save, _ type: EventType, moment: Moment? = nil, surface: String? = nil, detail: String? = nil) {
        context.insert(MomentEvent(saveId: save.id, momentId: moment?.id, type: type, at: now(), surface: surface, detail: detail))
    }
}

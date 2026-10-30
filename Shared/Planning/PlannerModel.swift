import Foundation
import FoundationModels
import ShoeboxCore

/// The on-device model's one job in planning (SPEC 4.1 step 2): read a reason the rules couldn't place and
/// return hints. It never does date arithmetic; the rules turn hints into times. Nothing leaves the phone.
@MainActor
enum PlannerModel {
    @Generable
    struct Reading {
        @Guide(description: "Month number 1 to 12 the reason points to, if any. 'when it gets cold' is 12, 'beach season' is 6. 0 if none.")
        var month: Int
        @Guide(description: "True if the thing needs to start a day ahead: an overnight step, a delivery, a booking.")
        var needsDayAhead: Bool
        @Guide(description: "True if this sounds like a weekend project rather than a quick read.")
        var weekendProject: Bool
        @Guide(description: "Words from the reason that name a calendar event, or empty.")
        var eventWords: String
    }

    static var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Hints for one save, or nil when the model isn't available or isn't needed.
    static func hints(reason: String, title: String, kind: SaveKind, minutes: Int?, events: [CalendarEventInfo]) async -> ModelHints? {
        guard available else { return nil }
        let session = LanguageModelSession(instructions: """
            You help a read-later app decide when a saved thing should come back. You only read the person's reason \
            and the saved thing's title. You never invent dates. Answer with the fields asked for.
            """)
        let titles = events.prefix(30).map(\.title).joined(separator: "; ")
        let prompt = """
            Reason: \(reason.isEmpty ? "(none)" : reason)
            Saved: \(kind.rawValue), \(title), about \(minutes ?? 5) minutes
            Calendar event titles: \(titles.isEmpty ? "(none)" : titles)
            """
        guard let r = try? await session.respond(to: prompt, generating: Reading.self).content else { return nil }
        var h = ModelHints()
        h.monthHint = (1...12).contains(r.month) ? r.month : nil
        h.needsDayAhead = r.needsDayAhead
        h.weekendProject = r.weekendProject
        let words = r.eventWords.lowercased()
        if !words.isEmpty {
            h.anchorEventId = events.first { e in words.split(separator: " ").contains { w in w.count > 3 && e.title.lowercased().contains(w) } }?.id
        }
        return h
    }

    /// Re-plans a save with the model's hints when the rules only guessed. The change shows in Coming back,
    /// never as a new notification (SPEC 4.7).
    static func refine(_ save: Save, keeper: Keeper, events: [CalendarEventInfo]) async {
        guard available, save.modelPlannedAt == nil, !save.reason.isEmpty, let m = keeper.nextMoment(for: save),
              m.confidence == .guess || ReturnPlanner.needsModel(save.reason) else { return }
        save.modelPlannedAt = keeper.now()
        guard let h = await hints(reason: save.reason, title: save.title, kind: save.kind, minutes: save.minutes, events: events) else { return }
        guard save.status == .planned, save.nextMomentId == m.id else { return }
        keeper.plan(save, events: events, hints: h)
        try? keeper.context.save()
    }
}

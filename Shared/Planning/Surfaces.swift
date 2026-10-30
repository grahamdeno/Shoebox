import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import WidgetKit
import ActivityKit
import ShoeboxCore

/// Spotlight finds saves by your words (SPEC moment 7). Deleted saves are removed from the index.
enum Spotlight {
    @MainActor
    static func index(_ saves: [Save]) {
        let index = CSSearchableIndex.default()
        let gone = saves.filter { $0.deletedAt != nil }.map { $0.id.uuidString }
        if !gone.isEmpty { index.deleteSearchableItems(withIdentifiers: gone) { _ in } }
        let items: [CSSearchableItem] = saves.filter { $0.deletedAt == nil }.map { s in
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = s.headline
            a.contentDescription = s.reason.isEmpty ? (s.summary.isEmpty ? s.host : s.summary) : s.title
            a.keywords = s.tags
            if let u = s.url { a.url = URL(string: u) }
            return CSSearchableItem(uniqueIdentifier: s.id.uuidString, domainIdentifier: "saves", attributeSet: a)
        }
        if !items.isEmpty { index.indexSearchableItems(items) { _ in } }
    }
}

enum WidgetsBridge {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}

/// The Live Activity for a save that comes back just before a calendar event (SPEC rule R3, moment 3).
struct MomentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var eventStart: Date
        var eventTitle: String
    }
    var saveId: String
    var reason: String
    var title: String
    var minutes: Int
    var doneWord: String
}

@MainActor
enum LiveMoments {
    /// Starts a Live Activity for moments that begin within 30 minutes and ends ones whose event has started.
    /// [Check] Local apps can only start one while running, so the moment also has a time-sensitive notification.
    static func update(_ keeper: Keeper) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = keeper.now()
        await endStarted(before: now)
        let live = Activity<MomentActivityAttributes>.activities
        for m in keeper.openMoments() where m.surface == .liveActivity && m.start <= now.addingTimeInterval(1800) && m.end > now {
            guard let s = keeper.save(id: m.saveId), s.nextMomentId == m.id,
                  !live.contains(where: { $0.attributes.saveId == s.id.uuidString }) else { continue }
            let title = m.anchorEventId.flatMap(CalendarReader.event(id:))?.title ?? m.explanation
            let attrs = MomentActivityAttributes(saveId: s.id.uuidString, reason: s.headline, title: s.title,
                                                 minutes: s.minutes ?? 5, doneWord: Engine.doneWord(s))
            let state = MomentActivityAttributes.ContentState(eventStart: m.end, eventTitle: title)
            _ = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: m.end), pushType: nil)
        }
    }

    nonisolated static func endStarted(before now: Date) async {
        for a in Activity<MomentActivityAttributes>.activities where a.content.state.eventStart <= now {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated static func end(saveId: UUID) async {
        for a in Activity<MomentActivityAttributes>.activities where a.attributes.saveId == saveId.uuidString {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}

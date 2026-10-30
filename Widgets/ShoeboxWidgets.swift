import WidgetKit
import SwiftUI
import SwiftData
import ActivityKit
import AppIntents
import ShoeboxCore

@main
struct ShoeboxWidgets: WidgetBundle {
    var body: some Widget {
        ComingBackWidget()
        MomentLiveActivity()
    }
}

// MARK: Coming back widget (Home Screen and Lock Screen)

struct ComingEntry: TimelineEntry {
    struct Row: Hashable { var id: UUID; var reason: String; var when: String; var day: String }
    var date: Date
    var rows: [Row]
}

struct ComingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComingEntry {
        ComingEntry(date: .now, rows: [.init(id: UUID(), reason: "Read before we plan next quarter", when: "Back at 9:48", day: "Thu")])
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ComingEntry) -> Void) {
        Task { @MainActor in completion(Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ComingEntry>) -> Void) {
        Task { @MainActor in
            let e = Self.load()
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(3600))))
        }
    }

    @MainActor
    static func load() -> ComingEntry {
        let k = Keeper.shared()
        let rows = k.openMoments().filter { $0.start > .now.addingTimeInterval(-3600) }.compactMap { m -> ComingEntry.Row? in
            guard let s = k.save(id: m.saveId), s.nextMomentId == m.id, s.deletedAt == nil else { return nil }
            return .init(id: s.id, reason: s.headline, when: m.explanation, day: Phrases.day(m.start))
        }
        return ComingEntry(date: .now, rows: Array(rows.prefix(3)))
    }
}

struct ComingBackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComingBack", provider: ComingProvider()) { entry in
            ComingWidgetView(entry: entry).containerBackground(for: .widget) { Theme.roles.surface }
        }
        .configurationDisplayName("Coming back")
        .description("What's coming back next, in your words.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ComingWidgetView: View {
    let entry: ComingEntry
    @Environment(\.widgetFamily) private var family
    private var roles: ColorRoles { Theme.roles }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.rows.first.map { "\($0.day): \($0.reason)" } ?? "Nothing coming back")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.rows.first?.day ?? "Shoebox").font(.caption2.weight(.semibold)).textCase(.uppercase)
                Text(entry.rows.first?.reason ?? "Nothing coming back").font(.shoebox(.reasonSm)).lineLimit(2)
            }
            .widgetURL(entry.rows.first.flatMap { URL(string: "shoebox://save/\($0.id.uuidString)") })
        default:
            VStack(alignment: .leading, spacing: Metric.space2) {
                HStack(spacing: Metric.space2) { AppMark(); Text("Coming back").type(.meta).foregroundStyle(roles.quiet) }
                if entry.rows.isEmpty {
                    Text("Nothing yet. Share anything to Shoebox.").type(.label).foregroundStyle(roles.quiet)
                }
                ForEach(entry.rows.prefix(family == .systemSmall ? 1 : 3), id: \.self) { r in
                    Link(destination: URL(string: "shoebox://save/\(r.id.uuidString)")!) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.reason).type(family == .systemSmall ? .reasonMd : .reasonSm).foregroundStyle(roles.text).lineLimit(family == .systemSmall ? 4 : 2)
                            Text(r.day + " · " + r.when).type(.label).foregroundStyle(roles.quiet).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .environment(\.roles, roles)
        }
    }
}

// MARK: The Live Activity (moment 3)

struct MomentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MomentActivityAttributes.self) { context in
            LockScreenMoment(context: context).environment(\.roles, Theme.roles)
                .activityBackgroundTint(Theme.roles.surface)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { AppMark().environment(\.roles, Theme.roles) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(Date.now, context.state.eventStart), countsDown: true).monospacedDigit().frame(width: 56)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.reason).font(.shoebox(.reasonSm)).lineLimit(2)
                        Text("\(context.attributes.minutes) min, before \(context.state.eventTitle)").font(.caption)
                        HStack {
                            Button(intent: MomentDoneIntent(saveId: context.attributes.saveId)) { Text(context.attributes.doneWord) }
                            Button(intent: MomentLaterIntent(saveId: context.attributes.saveId)) { Text("Later") }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "tray")
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.eventStart), countsDown: true).monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: "tray")
            }
            .widgetURL(URL(string: "shoebox://save/\(context.attributes.saveId)"))
        }
    }
}

struct LockScreenMoment: View {
    let context: ActivityViewContext<MomentActivityAttributes>
    @Environment(\.roles) private var roles

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.space2) {
            HStack(spacing: Metric.space2) {
                AppMark()
                Text("Before \(context.state.eventTitle)").type(.meta).foregroundStyle(roles.quiet).lineLimit(1)
                Spacer()
                Text(timerInterval: Date.now...max(Date.now, context.state.eventStart), countsDown: true)
                    .type(.label).monospacedDigit().foregroundStyle(roles.text).frame(width: 52, alignment: .trailing)
            }
            Text(context.attributes.reason).type(.reasonMd).foregroundStyle(roles.text).lineLimit(2)
            Text("\(context.attributes.title) · \(context.attributes.minutes) min").type(.label).foregroundStyle(roles.quiet).lineLimit(1)
            HStack(spacing: Metric.space2) {
                Button(intent: MomentDoneIntent(saveId: context.attributes.saveId)) { Text(context.attributes.doneWord) }.buttonStyle(ActButtonStyle())
                Button(intent: MomentLaterIntent(saveId: context.attributes.saveId)) { Text("Later") }.buttonStyle(LineButtonStyle())
                Button(intent: MomentDropIntent(saveId: context.attributes.saveId)) { Text("Drop") }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Metric.space3)
    }
}

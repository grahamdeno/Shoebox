import SwiftUI
import SwiftData
import ShoeboxCore

/// Everything kept: one question away. Coming back, done, let go and quiet, all searchable.
struct EverythingView: View {
    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all = "All", coming = "Coming back", done = "Done", quiet = "Quiet", letGo = "Let go"
        var id: String { rawValue }
    }

    @State var filter: Filter
    @State var query: String = ""
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Save> { $0.deletedAt == nil }, sort: \Save.createdAt, order: .reverse) private var saves: [Save]

    private var keeper: Keeper { Keeper(context: context) }

    private var shown: [Save] {
        let base = query.isEmpty ? saves : keeper.search(query)
        return base.filter { s in
            switch filter {
            case .all: true
            case .coming: s.status == .planned || s.status == .unplanned
            case .done: s.status == .done
            case .quiet: s.status == .quiet
            case .letGo: s.status == .dropped
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(roles.text)
                .listRowBackground(roles.surface)
            }
            if shown.isEmpty {
                Text(query.isEmpty ? "Nothing here." : "Nothing kept matches \u{201C}\(query)\u{201D}.")
                    .type(.body).foregroundStyle(roles.quiet).listRowBackground(roles.surface)
            }
            ForEach(shown) { s in
                NavigationLink(value: AppModel.Route.save(s.id)) {
                    VStack(alignment: .leading, spacing: Metric.space1) {
                        Text(s.headline).type(.reasonSm).foregroundStyle(roles.text).lineLimit(3)
                        HStack(spacing: Metric.space2) {
                            if s.status == .quiet { tag("Quiet") }
                            if s.status == .done { tag("Done") }
                            if s.status == .dropped { tag("Let go") }
                            Text(line(s)).type(.label).foregroundStyle(roles.quiet).lineLimit(1)
                        }
                    }
                    .padding(.vertical, Metric.space2)
                }
                .listRowBackground(roles.surface)
                .listRowSeparatorTint(roles.line)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(roles.surface)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "What did I keep about…")
        .navigationTitle("Everything kept")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tag(_ t: String) -> some View {
        Text(t).type(.meta).foregroundStyle(t == "Done" ? roles.done : roles.quiet)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
    }

    private func line(_ s: Save) -> String {
        var parts: [String] = []
        if !s.reason.isEmpty { parts.append(s.title) }
        if let h = s.host { parts.append(h) }
        parts.append(s.createdAt.formatted(.dateTime.month(.abbreviated).day()))
        return parts.joined(separator: " · ")
    }
}

/// Keep something from inside the app: paste, or type a note.
struct InAppCapture: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roles) private var roles
    @State private var pasted: String?
    @State private var note = ""
    @State private var box = SavedBox()

    final class SavedBox { var saves: [Save] = [] }

    var body: some View {
        if let text = pasted {
            capture(text)
        } else {
            VStack(alignment: .leading, spacing: Metric.space4) {
                Text("Keep something").type(.title)
                PasteButton(payloadType: String.self) { items in
                    Task { @MainActor in pasted = items.joined(separator: "\n") }
                }
                .buttonBorderShape(.roundedRectangle(radius: Metric.radiusSm))
                .tint(roles.act)
                Text("Or write a note").type(.label).foregroundStyle(roles.quiet)
                TextField("", text: $note, prompt: Text("A thought, a list, a name"), axis: .vertical)
                    .type(.body).lineLimit(3...8)
                    .padding(Metric.space3)
                    .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
                Button("Next") { pasted = note }.buttonStyle(LineButtonStyle()).disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(Metric.space5)
        }
    }

    private func capture(_ text: String) -> some View {
        let drafts = Detection.drafts(fromText: text)
        let first = drafts.first ?? Detection.Draft(kind: .note, title: String(text.prefix(90)), text: text, url: nil, author: nil, videoId: nil, imageURL: nil)
        let keeper = Keeper(context: context)
        let events = CalendarReader.upcoming()
        let box = self.box
        return CaptureView(
            found: ShareFound.label(first, count: drafts.count),
            title: first.title,
            onSave: { reason, spoken in
                var last: PlanOutcome?
                for d in drafts.isEmpty ? [first] : drafts {
                    let (s, o) = keeper.keep(d, reason: reason, reasonSource: spoken ? .spoken : .typed, source: .paste, events: events)
                    box.saves.append(s); last = o
                }
                Task { await model.refresh() }
                return last ?? .moment(PlannedMoment(start: .now, end: .now, surface: .issue, place: .any, ruleId: "R20", confidence: .guess,
                                                     explanation: "Kept", laterLabel: "Tomorrow", anchorEventId: nil))
            },
            onChange: { c in
                var p: PlannedMoment?
                for s in box.saves { p = keeper.later(s, c, events: events, surface: "app") }
                Task { await model.refresh() }
                return p ?? ReturnPlanner.later(c, input: PlanInput(reason: "", kind: .note, minutes: nil, intent: nil, title: "", now: .now, events: [], plannedPerDay: [:], hints: nil))
            },
            onPick: { d in for s in box.saves { keeper.later(s, at: d, surface: "app") }; Task { await model.refresh() } },
            onClose: { dismiss() }
        )
    }
}

enum ShareFound {
    static func label(_ d: Detection.Draft, count: Int) -> String {
        let what: String = switch d.kind {
        case .link: count > 1 ? "\(count) links" : "Link"
        case .video: "Video"
        case .photo: "Photo"
        case .pdf: "PDF"
        case .quote: "Quote"
        case .note: "Note"
        case .file: "File"
        }
        let host = d.url.flatMap(URL.init(string:))?.host()?.replacingOccurrences(of: "www.", with: "")
        return [what, host].compactMap { $0 }.joined(separator: " · ")
    }
}

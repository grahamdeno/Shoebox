import SwiftUI
import SwiftData
import ShoeboxCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var onboarding = !Prefs.load().onboarded

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ComingBackView()
                .navigationDestination(for: AppModel.Route.self) { route in
                    switch route {
                    case .save(let id): SaveDetailView(id: id)
                    case .everything(let f, let q): EverythingView(filter: f, query: q)
                    }
                }
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView { onboarding = false } }
        .overlay(alignment: .bottom) { ToastView() }
        .task {
            if StoreBox.demo {
                Demo.seed(Keeper(context: context))
                onboarding = Demo.screen == "onboarding"
                switch Demo.screen {
                case "detail": model.showing = Keeper(context: context).allSaves().first { $0.reason.hasPrefix("Read before") }?.id
                case "capture": model.capturing = true
                case "everything": model.searching = true
                case "post": model.showing = Keeper(context: context).allSaves().first { $0.isSchool && $0.dueKindRaw == "todo" }?.id
                default: break
                }
                return
            }
            if Prefs.load().onboarded, let text = await ImportService.autoImport(keeper: Keeper(context: context)) {
                model.toast = .init(text: text, undo: nil)
            }
            await model.refresh()
        }
    }
}

/// Moment 10: Coming back by date; everything kept one question away.
struct ComingBackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Save> { $0.deletedAt == nil }, sort: \Save.createdAt, order: .reverse) private var saves: [Save]
    @Query(sort: \Moment.start) private var moments: [Moment]
    @State private var question = ""
    @State private var settings = false

    private var keeper: Keeper { Keeper(context: context) }

    /// Planned saves with their open moment, grouped by day.
    private var days: [(day: Date, rows: [(Save, Moment)])] {
        let byId = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = saves.compactMap { s -> (Save, Moment)? in
            guard s.status == .planned, !s.inInbox, let id = s.nextMomentId, let m = byId[id] else { return nil }
            return (s, m)
        }.sorted { $0.1.start < $1.1.start }
        let cal = Calendar.current
        let groups = Dictionary(grouping: rows) { cal.startOfDay(for: $0.1.start) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private var inbox: [Save] { saves.filter(\.inInbox).sorted { ($0.inboxAt ?? .distantPast) > ($1.inboxAt ?? .distantPast) } }

    private var quietCount: Int { saves.filter { $0.status == .quiet }.count }
    private var unplanned: [Save] { saves.filter { $0.status == .unplanned } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !inbox.isEmpty { inboxSection }
                if days.isEmpty && unplanned.isEmpty && inbox.isEmpty { empty } else {
                    ForEach(days, id: \.day) { group in
                        ForEach(Array(group.rows.enumerated()), id: \.element.0.id) { i, pair in
                            NavigationLink(value: AppModel.Route.save(pair.0.id)) {
                                ComingBackRow(save: pair.0, moment: pair.1, showDay: i == 0, picture: keeper.picture(for: pair.0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !unplanned.isEmpty {
                        Text("Finding a time for \(unplanned.count)").type(.label).foregroundStyle(roles.quiet).padding(.top, Metric.space4)
                    }
                }
                if quietCount > 0 {
                    NavigationLink(value: AppModel.Route.everything(.quiet, "")) {
                        HStack {
                            Text("\(quietCount) gone quiet").type(.label).foregroundStyle(roles.quiet)
                            Spacer()
                            Text("Kept, not offered").type(.label).foregroundStyle(roles.quiet)
                        }
                        .padding(Metric.space3)
                        .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, style: StrokeStyle(lineWidth: Metric.hairline, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Metric.space6)
                }
                NavigationLink(value: AppModel.Route.everything(.all, "")) {
                    HStack { Text("Everything kept").type(.title); Spacer(); Text("\(saves.count)").type(.label).foregroundStyle(roles.quiet); Image(systemName: "chevron.right").foregroundStyle(roles.quiet) }
                        .frame(minHeight: Metric.tap)
                }
                .buttonStyle(.plain)
                .padding(.top, Metric.space6)
                Spacer(minLength: 120)
            }
            .padding(.horizontal, Metric.space5)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(roles.surface)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Bindable(model).capturing) { InAppCapture().themed(model.roles).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() }.themed(model.roles) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metric.space3) {
        if StoreBox.shared.failed {
            Text("Shoebox couldn't open your saves on this iPhone. Nothing has been changed or deleted. Restart your iPhone, then open Shoebox again.")
                .type(.label).foregroundStyle(roles.text).padding(Metric.space3)
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
        }
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Metric.space1) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).type(.meta).foregroundStyle(roles.quiet)
                Text("Coming back").type(.reasonSm).foregroundStyle(roles.text)
            }
            Spacer()
            Button { settings = true } label: { Image(systemName: "gearshape").foregroundStyle(roles.quiet).frame(width: Metric.tap, height: Metric.tap) }
                .accessibilityLabel("Settings")
        }
        }
        .padding(.top, Metric.space4)
        .padding(.bottom, Metric.space4)
    }

    /// SPEC 7.6: what came by email waits here to Keep or Drop. It still comes back on time if you never sort it.
    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("From your email").type(.meta).foregroundStyle(roles.quiet)
                Spacer()
                Text("\(inbox.count)").type(.meta).foregroundStyle(roles.quiet)
            }
            .padding(.bottom, Metric.space2)
            ForEach(inbox) { s in
                VStack(alignment: .leading, spacing: Metric.space2) {
                    NavigationLink(value: AppModel.Route.save(s.id)) {
                        VStack(alignment: .leading, spacing: Metric.space1) {
                            Text(s.headline).type(.reasonSm).foregroundStyle(roles.text).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(inboxLine(s)).type(.label).foregroundStyle(roles.quiet).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: Metric.space2) {
                        Button("Keep") { keeper.keepFromInbox(s) }.buttonStyle(LineButtonStyle()).frame(maxWidth: 120)
                        Button("Drop") { keeper.drop(s, surface: "inbox"); Task { await model.refresh() } }.buttonStyle(QuietButtonStyle())
                        Spacer()
                    }
                }
                .padding(.vertical, Metric.space3)
                .overlay(alignment: .top) { Hairline() }
            }
        }
        .padding(.bottom, Metric.space5)
    }

    private func inboxLine(_ s: Save) -> String {
        var parts: [String] = []
        if let d = s.dueDate { parts.append(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
        if let m = keeper.nextMoment(for: s) { parts.append(m.explanation) }
        if let f = s.emailFromName ?? s.emailFrom { parts.append(f) }
        return parts.joined(separator: " · ")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Metric.space3) {
            Hairline()
            Text("Nothing coming back yet.").type(.reasonMd).padding(.top, Metric.space4)
            Text("Share anything to Shoebox and say why you're keeping it. It comes back when it's useful.")
                .type(.body).foregroundStyle(roles.quiet)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Metric.space2) {
            HStack(spacing: Metric.space2) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(roles.quiet)
                    TextField("", text: $question, prompt: Text("What did I keep about…").foregroundStyle(roles.quiet))
                        .type(.body).submitLabel(.search)
                        .onSubmit { if !question.isEmpty { model.searchText = question; model.searching = true; question = "" } }
                }
                .padding(.horizontal, Metric.space3)
                .frame(minHeight: Metric.tap)
                .background(roles.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
                Button { model.capturing = true } label: { Label("Keep", systemImage: "plus").labelStyle(.titleAndIcon) }
                    .buttonStyle(ActButtonStyle()).frame(width: 104)
            }
        }
        .padding(.horizontal, Metric.space5)
        .padding(.vertical, Metric.space3)
        .background(roles.surface)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// The Coming back row (Design System: ComingBackRow): day column, your reason, the source line.
struct ComingBackRow: View {
    let save: Save
    let moment: Moment
    let showDay: Bool
    let picture: URL?
    @Environment(\.roles) private var roles

    var body: some View {
        HStack(alignment: .top, spacing: Metric.space3) {
            VStack(alignment: .leading, spacing: 0) {
                if showDay {
                    Text(dayName).type(.meta).foregroundStyle(roles.quiet)
                    Text(moment.start.formatted(.dateTime.day())).type(.dayNumeral).foregroundStyle(roles.text).padding(.top, 2)
                }
            }
            .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: Metric.space1) {
                Text(save.headline).type(.reasonMd).foregroundStyle(roles.text).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceLine).type(.label).foregroundStyle(roles.quiet).lineLimit(1)
                Text(moment.explanation).type(.label).foregroundStyle(roles.quiet)
            }
            Spacer(minLength: 0)
            if let picture, let img = UIImage(contentsOfFile: picture.path()) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.radiusPicture))
                    .accessibilityLabel(save.alt.isEmpty ? "Picture" : save.alt)
            }
        }
        .padding(.vertical, Metric.space4)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dayName: String {
        let cal = Calendar.current
        if cal.isDateInToday(moment.start) { return "Today" }
        if cal.isDateInTomorrow(moment.start) { return "Tmrw" }
        return moment.start.formatted(.dateTime.weekday(.abbreviated))
    }

    private var sourceLine: String {
        var parts: [String] = []
        if !save.reason.isEmpty { parts.append(save.title) }
        if let h = save.host { parts.append(h) }
        if let m = save.minutes, save.kind != .photo, save.kind != .quote { parts.append("\(m) min") }
        return parts.joined(separator: " · ")
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    var body: some View {
        if let t = model.toast {
            HStack {
                Text(t.text).type(.body).foregroundStyle(roles.surface)
                Spacer()
                if let id = t.undo {
                    Button("Undo") {
                        let k = Keeper(context: context)
                        if let s = k.save(id: id) { k.bringBack(s, .youChoose, events: CalendarReader.upcoming()) }
                        model.toast = nil
                        Task { await model.refresh() }
                    }
                    .type(.button).foregroundStyle(roles.surface)
                }
            }
            .padding(Metric.space4)
            .background(roles.text, in: RoundedRectangle(cornerRadius: Metric.radiusMd))
            .padding(.horizontal, Metric.space5)
            .padding(.bottom, 80)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: t) {
                try? await Task.sleep(for: .seconds(8))
                if model.toast == t { model.toast = nil }
            }
        }
    }
}

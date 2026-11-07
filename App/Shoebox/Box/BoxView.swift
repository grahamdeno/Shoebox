import SwiftData
import ShoeboxCore
import SwiftUI
import UIKit

/// The Shoebox: everything you are not done with, in the order the stack will bring it. What you put away
/// (done) is out of the list until you ask for it with one word at the top right. Searching looks everywhere.
struct BoxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Save.createdAt) private var all: [Save]
    @State private var search = ""
    @State private var showPutAway = false
    /// The topics that are open in Put away. All start closed.
    @State private var openTopics: Set<String> = []
    @State private var opened: OpenedPost?
    @State private var toast: Toast?
    /// How high the keyboard stands over the bottom of the screen, so the search field rides it.
    @State private var keyboard: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let planner: LaterPlanner
    /// Tells the Shoebox when it has been closed, so a showing Undo can move to Today.
    var pull: BoxPull?
    /// Today is already showing an opened post: this sheet opens none until it is closed, so two covers never stack.
    var otherPostOpen = false
    /// Closes the Shoebox (it is a sheet that slides out from behind the box on Today).
    var onClose: () -> Void = {}
    var onBringBack: (Save) -> Void
    /// "Go through them one at a time": close the Shoebox and bring them out on Today.
    var onBrowse: () -> Void = {}
    /// Settings is shown by Today, not by the Shoebox sheet, so it opens the same way every time.
    var onSettings: () -> Void = {}
    /// The Box is closing while its Undo is still showing: Today shows it instead, so it can still be undone.
    var onHandOff: (Toast) -> Void = { _ in }
    /// Pulling down on the top of the Shoebox closes it. Buttons there still tap.
    var pullGesture: AnyGesture<Void> = AnyGesture(DragGesture(minimumDistance: 100_000).map { _ in () })

    private let rules = TodayRules()
    private let actions = SaveActions()
    private var now: Date { Clock.now }

    private func matches(_ s: Save) -> Bool {
        search.isEmpty || s.title.localizedCaseInsensitiveContains(search)
            || s.note.localizedCaseInsensitiveContains(search)
            || s.snippet.localizedCaseInsensitiveContains(search)
            || s.body.localizedCaseInsensitiveContains(search)
            || (s.urlString ?? "").localizedCaseInsensitiveContains(search)
    }

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }
    private var putAwayAll: [Save] { rules.kept(all) }
    private var putAway: [Save] { putAwayAll.filter(matches) }
    private let putAwayLog = PutAwayLog.shared

    /// How far ahead Coming up looks. Anything dated later waits in Everything else until it's close.
    private var horizon: Date { Calendar.current.date(byAdding: .month, value: 2, to: now) ?? now }

    private func isComingUp(_ s: Save) -> Bool {
        guard let day = s.eventDate else { return false }
        return day <= horizon
    }

    /// Posts dated in the next two months, soonest first. A fact about the post, not a guess.
    private var comingUp: [Save] {
        rules.library(all, now: now).filter { isComingUp($0) && matches($0) }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }

    /// Everything else not put away, newest first.
    private var everythingElse: [Save] {
        rules.library(all, now: now).filter { !isComingUp($0) && matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filterWord: String? {
        if showPutAway { return "Shoebox" }
        return putAwayAll.isEmpty ? nil : "Put away (\(putAwayAll.count))"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("Today") { onClose() }
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 88, minHeight: Metrics.touchMin, alignment: .leading)
                        .contentShape(Rectangle())
                    Spacer()
                    Button("Settings") { onSettings() }
                        .scaledFont(size: 17)
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 110, minHeight: 56, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                HStack(alignment: .firstTextBaseline) {
                    Text(showPutAway ? "Put away" : "Shoebox")
                        .scaledFont(size: 34, weight: .semibold)
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let word = filterWord {
                        Button(word) {
                            withAnimation(.snappy) { showPutAway.toggle() }
                        }
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(pullGesture)

                List {
                    if showPutAway {
                        if putAway.isEmpty { plain(empty(searching ? "Nothing found." : "Nothing put away yet.")) }
                        if searching {
                            ForEach(putAway, id: \.id) { listRow($0, dim: true) }
                        } else {
                            // What you put away in the last 3 days, newest first, always open, above the topics (SPEC 2.4).
                            let recent = putAwayLog.recent(putAway, now: now)
                            if !recent.isEmpty {
                                plain(sectionTitle("Just put away"))
                                ForEach(recent, id: \.id) { listRow($0, dim: true, quietLine: putAwayLog.line($0, now: now)) }
                                plain(sectionTitle("By topic"))
                            }
                            // Put away by topic, each one closed until tapped, like Scales' Insights (SPEC 2.4).
                            let byID = Dictionary(putAway.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
                            ForEach(Tidy.topics(putAway.map(\.tidyItem)), id: \.topic) { group in
                                plain(topicHeader(group, byID))
                                if openTopics.contains(group.topic.rawValue) {
                                    ForEach(group.rows, id: \.id) { r in
                                        if let s = byID[r.id] { listRow(s, dim: true) }
                                    }
                                }
                            }
                        }
                    } else {
                        let up = comingUp
                        let rest = everythingElse
                        if up.isEmpty && rest.isEmpty && !(searching && !putAway.isEmpty) {
                            plain(empty(searching ? "Nothing found." : "Nothing waiting. Everything is put away."))
                        }
                        if !up.isEmpty {
                            plain(sectionTitle("Coming up"))
                            ForEach(up, id: \.id) { listRow($0, dim: false, dated: true) }
                        }
                        if !rest.isEmpty {
                            plain(sectionTitle("Everything else"))
                            ForEach(rest, id: \.id) { listRow($0, dim: false) }
                        }
                        // Searching looks everywhere, so what you put away can still be found.
                        if searching && !putAway.isEmpty {
                            plain(sectionTitle("Put away"))
                            ForEach(putAway, id: \.id) { listRow($0, dim: true) }
                        }
                        if !searching && !(up.isEmpty && rest.isEmpty) {
                            plain(
                                Button(action: onBrowse) {
                                    HStack {
                                        Text("Go through them one at a time")
                                            .scaledFont(size: 16, weight: .semibold)
                                            .foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text("\u{203A}").scaledFont(size: 22).foregroundStyle(Theme.quiet)
                                    }
                                    .frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 26)
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // The list is a UIKit collection underneath; hide it here too, not only on the sheet around it.
                .accessibilityHidden((pull?.progress ?? 1) <= 0.02 && !(pull?.dragging ?? false))
                // The last row stops well above the home indicator, not on it.
                .contentMargins(.bottom, 130, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollDismissesKeyboard(.interactively)
            }

            searchField

            if let toast {
                HStack {
                    Spacer()
                    UndoPill(text: toast.text) {
                        toast.undo()
                        withAnimation(.snappy) { self.toast = nil }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 92 + keyboard)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds.height
            withAnimation(.easeOut(duration: 0.25)) { keyboard = max(0, screen - end.minY) }
        }
        .fullScreenCover(item: $opened) { item in
            let save = item.save
            OpenedView(
                save: save,
                onClose: { opened = nil },
                onNotNow: { opened = nil; perform(on: save) { actions.next($0, planner: planner, now: now) } },
                onPutAway: { opened = nil; perform(on: save) { actions.done($0, now: now); return "Put away" } },
                onBringBack: { opened = nil; onBringBack(save) },
                onDelete: { opened = nil; perform(on: save) { actions.letGo($0, now: now); return "Deleted" } }
            )
        }
        .onChange(of: pull?.closedTick ?? 0) { _, _ in
            if let toast { onHandOff(toast); self.toast = nil }
        }
    }

    /// Search sits at the bottom, under the thumb: a glass field with no outline, riding the keyboard. The list fades into it.
    private var searchField: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Theme.boxGlass.opacity(0), Theme.boxGlass.opacity(0.9)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.6))
                    .frame(height: 130)
                    .allowsHitTesting(false)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .scaledFont(size: 16, weight: .medium)
                        .foregroundStyle(Theme.quiet)
                        .accessibilityHidden(true)
                    TextField("Search everything", text: $search)
                        .scaledFont(size: 17)
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.accent)
                        .submitLabel(.search)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    if reduceTransparency {
                        shape.fill(Theme.card)
                    } else {
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, max(30, keyboard + 8))
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Makes the change, keeps it, and shows Undo for 5 seconds.
    private func perform(on save: Save, _ change: (Save) -> String) {
        let snapshot = SaveSnapshot(save)
        let text = change(save)
        try? context.save()
        let new = Toast(text: text, undo: { snapshot.restore(save); try? context.save() })
        withAnimation(.snappy) { toast = new }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if toast?.id == new.id { withAnimation { toast = nil } }
        }
    }

    /// A list row that is not a post: no separator, no background, the same side margins as a post.
    private func plain<V: View>(_ content: V) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A post row. Swipe left to delete it: it leaves every list at once, stays in backups, and Undo shows for 5 seconds.
    private func listRow(_ s: Save, dim: Bool, dated: Bool = false, quietLine: String? = nil) -> some View {
        plain(row(s, dim: dim, dated: dated, quietLine: quietLine))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    perform(on: s) { actions.letGo($0, now: now); return "Deleted" }
                } label: {
                    Text("Delete").foregroundStyle(Theme.bone)
                }
                .tint(Theme.brick)
            }
    }

    /// A topic in Put away: its count large, its name, and the newest post in one quiet line. Tap to open or close.
    private func topicHeader(_ group: Tidy.Group, _ byID: [String: Save]) -> some View {
        let key = group.topic.rawValue
        let open = openTopics.contains(key)
        let newest = group.rows.first.flatMap { byID[$0.id] }
        return Button {
            withAnimation(.snappy) { if open { openTopics.remove(key) } else { openTopics.insert(key) } }
        } label: {
            HStack(alignment: .center, spacing: 18) {
                Text("\(group.count)")
                    .scaledFont(size: 34, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(key)
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    if let newest {
                        Text(newest.listTitle)
                            .scaledFont(size: 14)
                            .foregroundStyle(Theme.quiet)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("\u{203A}").scaledFont(size: 22).foregroundStyle(Theme.quiet)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key), \(group.count)")
        .accessibilityHint(open ? "Closes this topic" : "Shows these posts")
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 17)
            .foregroundStyle(Theme.quiet)
            .padding(.top, 24)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 12, weight: .semibold)
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(Theme.quiet)
            .padding(.top, 22)
            .padding(.bottom, 4)
    }

    /// One shape for every row: a date, or a picture only when the post has one; the words on up to two lines; one quiet
    /// line of where it came from. When you wrote a reason, the reason leads and the title moves to the quiet line.
    private func row(_ s: Save, dim: Bool, dated: Bool = false, quietLine: String? = nil) -> some View {
        let reason = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = s.listTitle
        let leads = reason.isEmpty ? title : reason
        let second = quietLine ?? meta(s)
        let quiet = (reason.isEmpty || reason == title) ? second : "\(title), \(second)"
        return Button { if opened == nil, !otherPostOpen { opened = OpenedPost(save: s) } } label: {
            HStack(spacing: 16) {
                if dated, let day = s.eventDate {
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .scaledFont(size: 11, weight: .semibold)
                            .tracking(0.8)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.quiet)
                        Text(day.formatted(.dateTime.day()))
                            .scaledFont(size: 24, weight: .medium)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(dim ? Theme.quiet : (soon(day) ? Theme.lid : Theme.ink))
                    }
                    .frame(minWidth: 40)
                } else if s.imageData != nil {
                    // A tile only for a real picture: never an empty or colored square.
                    RowThumb(save: s)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(leads)
                        .scaledFont(size: 17)
                        .foregroundStyle(dim ? Theme.quiet : Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(quiet)
                        .scaledFont(size: 14)
                        .foregroundStyle(Theme.quiet)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.bone.opacity(0.10)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A day within the next 7 days, today included.
    private func soon(_ day: Date) -> Bool {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: day)).day ?? 99
        return n >= 0 && n <= 7
    }

    /// "2 weeks ago, from Safari"
    private func meta(_ s: Save) -> String {
        s.byline().replacingOccurrences(of: "You, ", with: "")
    }
}

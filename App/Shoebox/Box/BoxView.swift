import SwiftData
import SwiftUI

/// The Shoebox: everything you are not done with, in the order the stack will bring it. What you put away
/// (done) is out of the list until you ask for it with one word at the top right. Searching looks everywhere.
struct BoxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Save.createdAt) private var all: [Save]
    @State private var search = ""
    @State private var showPutAway = false
    @State private var opened: OpenedPost?
    @State private var toast: Toast?

    let planner: LaterPlanner
    /// Tells the Shoebox when it has been closed, so a showing Undo can move to Today.
    var pull: BoxPull?
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
    private var now: Date { Date() }

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

    /// Posts with a date, soonest first. A fact about the post, not a guess.
    private var comingUp: [Save] {
        rules.library(all, now: now).filter { $0.eventDate != nil && matches($0) }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }

    /// Everything else not put away, newest first.
    private var everythingElse: [Save] {
        rules.library(all, now: now).filter { $0.eventDate == nil && matches($0) }
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 88, minHeight: Metrics.touchMin, alignment: .leading)
                        .contentShape(Rectangle())
                    Spacer()
                    Button("Settings") { onSettings() }
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 88, minHeight: Metrics.touchMin, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                HStack(alignment: .firstTextBaseline) {
                    Text(showPutAway ? "Put away" : "Shoebox")
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let word = filterWord {
                        Button(word) {
                            withAnimation(.snappy) { showPutAway.toggle() }
                        }
                        .font(.system(size: 16, weight: .semibold))
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

                TextField("Search everything", text: $search)
                    .font(.system(size: 16))
                    .well()
                    .padding(.horizontal, 24)
                    .submitLabel(.search)

                List {
                    if showPutAway {
                        if putAway.isEmpty { plain(empty(searching ? "Nothing found." : "Nothing put away yet.")) }
                        ForEach(putAway, id: \.id) { listRow($0, dim: true) }
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
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text("\u{203A}").font(.system(size: 22)).foregroundStyle(Theme.quiet)
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
                .environment(\.defaultMinListRowHeight, 1)
                .scrollDismissesKeyboard(.interactively)
            }

            if let toast {
                HStack {
                    Spacer()
                    UndoPill(text: toast.text) {
                        toast.undo()
                        withAnimation(.snappy) { self.toast = nil }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Theme.ground.ignoresSafeArea())
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
    private func listRow(_ s: Save, dim: Bool, dated: Bool = false) -> some View {
        plain(row(s, dim: dim, dated: dated))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    perform(on: s) { actions.letGo($0, now: now); return "Deleted" }
                } label: {
                    Text("Delete")
                }
            }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 24)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(Theme.quiet)
            .padding(.top, 22)
            .padding(.bottom, 4)
    }

    /// One shape for every row: a date or a small picture, one line of title, one quiet line of where it came from.
    private func row(_ s: Save, dim: Bool, dated: Bool = false) -> some View {
        Button { opened = OpenedPost(save: s) } label: {
            HStack(spacing: 14) {
                if dated, let day = s.eventDate {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.quiet)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 21, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(dim ? Theme.quiet : Theme.ink)
                    }
                    .frame(width: 42)
                } else {
                    RowThumb(save: s)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.headline)
                        .font(.system(size: 16))
                        .foregroundStyle(dim ? Theme.quiet : Theme.ink)
                        .lineLimit(1)
                    Text(meta(s))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.quiet)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "2 weeks ago, from Safari"
    private func meta(_ s: Save) -> String {
        s.byline().replacingOccurrences(of: "You, ", with: "")
    }
}

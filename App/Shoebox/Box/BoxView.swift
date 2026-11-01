import SwiftData
import SwiftUI

/// The Shoebox: everything you are not done with, in the order the stack will bring it. What you put away
/// (done) is out of the list until you ask for it with one word at the top right. Searching looks everywhere.
struct BoxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Save.createdAt) private var all: [Save]
    @State private var search = ""
    @State private var showSettings = false
    @State private var showPutAway = false
    @State private var opened: OpenedPost?
    @State private var toast: Toast?

    let planner: LaterPlanner
    /// Closes the Shoebox (it is a sheet that slides out from behind the box on Today).
    var onClose: () -> Void = {}
    var onBringBack: (Save) -> Void
    /// "Go through them one at a time": close the Shoebox and bring them out on Today.
    var onBrowse: () -> Void = {}
    /// The Box is closing while its Undo is still showing: Today shows it instead, so it can still be undone.
    var onHandOff: (Toast) -> Void = { _ in }

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
                HStack {
                    Button("Today") { onClose() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .leading)
                    Spacer()
                    Button("Settings") { showSettings = true }
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .trailing)
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

                TextField("Search everything", text: $search)
                    .font(.system(size: 16))
                    .well()
                    .padding(.horizontal, 24)
                    .submitLabel(.search)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if showPutAway {
                            if putAway.isEmpty { empty(searching ? "Nothing found." : "Nothing put away yet.") }
                            ForEach(putAway, id: \.id) { row($0, dim: true) }
                        } else {
                            let up = comingUp
                            let rest = everythingElse
                            if up.isEmpty && rest.isEmpty && !(searching && !putAway.isEmpty) {
                                empty(searching ? "Nothing found." : "Nothing waiting. Everything is put away.")
                            }
                            if !up.isEmpty {
                                sectionTitle("Coming up")
                                ForEach(up, id: \.id) { row($0, dim: false, dated: true) }
                            }
                            if !rest.isEmpty {
                                sectionTitle("Everything else")
                                ForEach(rest, id: \.id) { row($0, dim: false) }
                            }
                            // Searching looks everywhere, so what you put away can still be found.
                            if searching && !putAway.isEmpty {
                                sectionTitle("Put away")
                                ForEach(putAway, id: \.id) { row($0, dim: true) }
                            }
                            if !searching && !(up.isEmpty && rest.isEmpty) {
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
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
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
        .sheet(isPresented: $showSettings) { SettingsView() }
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
        .onDisappear { if let toast { onHandOff(toast) } }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "settings" { showSettings = true }
            #endif
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
                    thumb(s)
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

    /// The post's own picture, small; without one, the warm Onyx the post itself shows.
    @ViewBuilder
    private func thumb(_ s: Save) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if let data = s.imageData, let image = PhotoCache.entry(id: s.id, data: data)?.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(shape)
        } else {
            shape
                .fill(Theme.card)
                .overlay(RadialGradient(colors: [Theme.lid.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: 46).clipShape(shape))
                .frame(width: 42, height: 42)
        }
    }
}

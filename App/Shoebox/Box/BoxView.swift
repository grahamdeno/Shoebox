import SwiftData
import SwiftUI

/// The Shoebox: everything you are not done with, in the order the stack will bring it. What you put away
/// (done) is out of the list until you ask for it with one word at the top right. Searching looks everywhere.
struct BoxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Save.createdAt) private var all: [Save]
    @State private var search = ""
    @State private var showSettings = false
    @State private var showPutAway = false
    @State private var opened: OpenedPost?
    @State private var toast: Toast?

    let planner: LaterPlanner
    var onBringBack: (Save) -> Void
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

    /// The Shoebox list, grouped by when each post comes back. What is on Today now comes first.
    private var groups: [(label: String, items: [Save])] {
        var order: [String] = []
        var map: [String: [Save]] = [:]
        for s in rules.library(all, now: now) where matches(s) {
            let label = rules.comesBack(s, now: now).map { planner.label(for: $0, now: now) } ?? "On Today"
            if map[label] == nil { order.append(label) }
            map[label, default: []].append(s)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var filterWord: String? {
        if showPutAway { return "Shoebox" }
        return putAwayAll.isEmpty ? nil : "Put away (\(putAwayAll.count))"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("Today") { dismiss() }
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

                Text(showPutAway ? "Posts you are done with. Tap one to open it." : "Everything you are not done with. Tap one to open it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if showPutAway {
                            if putAway.isEmpty { empty(searching ? "Nothing found." : "Nothing put away yet.") }
                            ForEach(putAway, id: \.id) { row($0, dim: true) }
                        } else {
                            let g = groups
                            if g.isEmpty && !(searching && !putAway.isEmpty) {
                                empty(searching ? "Nothing found." : "Nothing waiting. Everything is put away.")
                            }
                            ForEach(g, id: \.label) { group in
                                sectionTitle(group.label)
                                ForEach(group.items, id: \.id) { row($0, dim: false) }
                            }
                            // Searching looks everywhere, so what you put away can still be found.
                            if searching && !putAway.isEmpty {
                                sectionTitle("Put away")
                                ForEach(putAway, id: \.id) { row($0, dim: true) }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 20)
            .padding(.bottom, 2)
    }

    private func row(_ s: Save, dim: Bool) -> some View {
        Button { opened = OpenedPost(save: s) } label: {
            Text(s.headline)
                .font(.system(size: 17))
                .foregroundStyle(dim ? Theme.quiet : Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: Metrics.touchMin, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

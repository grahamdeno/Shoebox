import SwiftData
import SwiftUI

/// What is put away, grouped by when it comes back, then what is kept. Searchable.
struct BoxView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Save.createdAt) private var all: [Save]
    @State private var search = ""
    @State private var showSettings = false

    let planner: LaterPlanner
    var onBringBack: (Save) -> Void

    private let rules = TodayRules()
    private var now: Date { Date() }

    private func matches(_ s: Save) -> Bool {
        search.isEmpty || s.title.localizedCaseInsensitiveContains(search)
            || s.note.localizedCaseInsensitiveContains(search)
            || s.snippet.localizedCaseInsensitiveContains(search)
            || s.body.localizedCaseInsensitiveContains(search)
            || (s.urlString ?? "").localizedCaseInsensitiveContains(search)
    }

    private var groups: [(label: String, items: [Save])] {
        var order: [String] = []
        var map: [String: [Save]] = [:]
        for s in rules.away(all, now: now) where matches(s) {
            let label = planner.label(for: s.returnDate ?? now, now: now)
            if map[label] == nil { order.append(label) }
            map[label, default: []].append(s)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var kept: [Save] { rules.kept(all).filter(matches) }

    var body: some View {
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

            Text("Box")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            TextField("Search everything you kept", text: $search)
                .font(.system(size: 16))
                .padding(14)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                .padding(.horizontal, 24)
                .submitLabel(.search)

            Text("Tap anything to bring it back to Today now.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.quiet)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty && kept.isEmpty {
                        Text(search.isEmpty ? "Nothing put away yet." : "Nothing found.")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.quiet)
                            .padding(.top, 24)
                    }
                    ForEach(groups, id: \.label) { group in
                        sectionTitle(group.label)
                        ForEach(group.items, id: \.id) { row($0, dim: false) }
                    }
                    if !kept.isEmpty {
                        sectionTitle("Kept")
                        ForEach(kept, id: \.id) { row($0, dim: true) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "settings" { showSettings = true }
            #endif
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 20)
            .padding(.bottom, 2)
    }

    private func row(_ s: Save, dim: Bool) -> some View {
        Button { onBringBack(s) } label: {
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

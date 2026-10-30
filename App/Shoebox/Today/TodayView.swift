import SwiftData
import SwiftUI
import UIKit

struct Toast: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void
}

/// A post being read. Wraps the save so the full-screen cover has a stable identity.
struct OpenedPost: Identifiable {
    let id = UUID()
    let save: Save
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Save.createdAt) private var all: [Save]

    @State private var pickIds: [String] = Prefs.pickIds
    @State private var showBox = false
    @State private var showAdd = false
    @State private var opened: OpenedPost?
    @State private var lidOpen = false
    @State private var pickingDate = false
    @State private var pickedDate = Date().addingTimeInterval(86_400)
    @State private var toast: Toast?
    @State private var dragOffset: CGFloat = 0
    @State private var datingSave: Save?

    private let rules = TodayRules()
    private let actions = SaveActions()
    private let planner = LaterPlanner()

    private var now: Date { Date() }
    private var queue: [Save] { rules.today(all, ids: pickIds, now: now) }
    private var awayCount: Int { rules.away(all, now: now).count }
    private var anyKept: Bool { all.contains { $0.deletedAt == nil } }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .opacity(lidOpen ? 0 : 1)
                if let current = queue.first {
                    PostView(save: current, planner: planner, now: now)
                        .id(current.id)
                        .offset(y: dragOffset)
                        .opacity(1 - Double(min(abs(dragOffset), 200)) / 400)
                        .gesture(swipe(for: current))
                        .onTapGesture { opened = OpenedPost(save: current) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens this post")
                        .accessibilityAction(named: "Next one") { pass(current) }
                        .task(id: current.id) { await enrichAhead() }
                    Text("Swipe up for the next one")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 24)
                        .padding(.bottom, 44)
                } else {
                    clearState
                }
            }
            .opacity(lidOpen ? 0.35 : 1)
            .saturation(lidOpen ? 0 : 1)
            .allowsHitTesting(!lidOpen)

            if let current = queue.first {
                lidLayer(for: current)
            }

            if let toast {
                toastView(toast)
            }
        }
        .onAppear {
            refreshPick()
            showScreenForScreenshots()
        }
        .onChange(of: phase) { _, p in if p == .active { refreshPick() } }
        .onChange(of: all.count) { _, _ in refreshPick() }
        .fullScreenCover(item: $opened) { item in
            let save = item.save
            OpenedView(
                save: save,
                planner: planner,
                onClose: { opened = nil },
                onDone: { opened = nil; done(save) },
                onLater: { choice in opened = nil; later(save, choice) },
                onPickDate: { opened = nil; datingSave = save; pickingDate = true },
                onLetGo: { opened = nil; letGo(save) }
            )
        }
        .fullScreenCover(isPresented: $showBox) {
            BoxView(planner: planner, onBringBack: { bringBack($0) })
        }
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
        .sheet(isPresented: $pickingDate) {
            datePicker
        }
    }

    // MARK: Layout

    private var topBar: some View {
        HStack {
            Button("Box") { showBox = true }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .leading)
            Spacer()
            if !queue.isEmpty {
                Text("\(queue.count) left today")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.quiet)
            }
            Spacer()
            Button { showAdd = true } label: {
                Text("+").font(.system(size: 28))
                    .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .trailing)
            }
            .foregroundStyle(Theme.ink)
            .accessibilityLabel("Keep something")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func lidLayer(for current: Save) -> some View {
        if lidOpen {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { lidOpen = false } }
        }
        VStack {
            Spacer()
            HStack {
                Spacer()
                if lidOpen {
                    LaterList(
                        suggestion: planner.suggestion(for: current, now: now),
                        options: planner.fixedOptions(now: now),
                        onPick: { lidOpen = false; later(current, $0) },
                        onPickDate: { lidOpen = false; datingSave = current; pickingDate = true },
                        onLetGo: { lidOpen = false; letGo(current) },
                        onClose: { withAnimation(.snappy) { lidOpen = false } }
                    )
                    .frame(width: 236)
                    .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
                } else {
                    BoxTop(
                        onTap: { withAnimation(.snappy) { lidOpen = true } },
                        onFlick: { opened = OpenedPost(save: current) }
                    )
                }
            }
            .padding(.trailing, Metrics.lidInset)
            .padding(.bottom, Metrics.lidBottom)
        }
    }

    private var clearState: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            BoxMark()
            VStack(alignment: .leading, spacing: 12) {
                Text(anyKept ? "Today's clear." : "Nothing kept yet.")
                    .font(.system(size: 38, weight: .semibold))
                    .tracking(-0.9)
                    .foregroundStyle(Theme.ink)
                Text(clearSubtitle)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.quiet)
                    .lineSpacing(3)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearSubtitle: String {
        if !anyKept { return "Share a page to Shoebox from Safari or any app, or tap + to keep something. Say why, and it comes back when it helps." }
        if awayCount == 0 { return "The next ones come out tomorrow." }
        let noun = awayCount == 1 ? "thing is" : "things are"
        return "\(awayCount) \(noun) waiting in the Box. The next ones come out tomorrow."
    }

    private func toastView(_ toast: Toast) -> some View {
        VStack {
            Spacer()
            HStack {
                Text(toast.text).font(.system(size: 15))
                Spacer()
                Button("Undo") { toast.undo(); self.toast = nil; refreshPick() }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: Metrics.touchMin)
            }
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 16)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, 16)
            .padding(.trailing, 16 + (queue.isEmpty ? 0 : Metrics.lidRestWidth + 8))
            .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var datePicker: some View {
        VStack(spacing: 16) {
            Text("Bring it back on")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
            DatePicker("Date", selection: $pickedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.ink)
                .labelsHidden()
            LidButton(title: "Put it away", width: 200, height: 56) {
                pickingDate = false
                if let save = datingSave ?? queue.first {
                    let start = Calendar.current.startOfDay(for: pickedDate)
                    let eight = Calendar.current.date(byAdding: .hour, value: 8, to: start) ?? start
                    later(save, LaterSuggestion(date: eight, label: planner.label(for: eight, now: now), reason: ""))
                }
                datingSave = nil
            }
            Button("Cancel") { pickingDate = false; datingSave = nil }
                .foregroundStyle(Theme.quiet)
                .frame(minHeight: Metrics.touchMin)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.large])
        .background(Theme.sheet)
    }

    // MARK: The day's pick

    private func refreshPick() {
        let ids = rules.pick(all, now: now, previousDay: Prefs.pickDay, previousIds: Prefs.pickIds, perDay: Prefs.perDay)
        Prefs.pickDay = rules.dayKey(now)
        Prefs.pickIds = ids
        if ids != pickIds { pickIds = ids }
    }

    /// Fills in link previews for the post on screen and the next two.
    private func enrichAhead() async {
        for s in queue.prefix(3) where s.enrichedAt == nil && s.url != nil {
            await Relay.enrich(s)
        }
        try? context.save()
    }

    /// Debug only: `-screen <name>` opens a screen for CI screenshots.
    private func showScreenForScreenshots() {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "screen") {
        case "lid": lidOpen = true
        case "opened": if let first = queue.first { opened = OpenedPost(save: first) }
        case "box", "settings": showBox = true
        case "add": showAdd = true
        default: break
        }
        #endif
    }

    // MARK: Gestures and actions

    private func swipe(for current: Save) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = min(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height < -90 {
                    withAnimation(.easeOut(duration: 0.15)) { dragOffset = -240 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        pass(current)
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    private func perform(_ text: String, on save: Save, _ change: (Save) -> Void) {
        let snapshot = SaveSnapshot(save)
        change(save)
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let new = Toast(text: text, undo: { snapshot.restore(save); try? context.save() })
        withAnimation(.snappy) { toast = new }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == new.id { withAnimation { toast = nil } }
        }
    }

    private func pass(_ save: Save) {
        perform(save.eventDate == nil ? "Back tomorrow" : "Back before the date", on: save) { actions.pass($0, now: now) }
    }

    private func done(_ save: Save) {
        perform("Done. Kept in the Box", on: save) { actions.done($0, now: now) }
    }

    private func later(_ save: Save, _ choice: LaterSuggestion) {
        perform("Back \(choice.label.lowercased())", on: save) {
            actions.later($0, until: choice.date, now: now)
        }
    }

    private func letGo(_ save: Save) {
        perform("Let go", on: save) { actions.letGo($0, now: now) }
    }

    private func bringBack(_ save: Save) {
        showBox = false
        perform("Back on Today", on: save) { actions.bringBack($0, now: now) }
        var ids = Prefs.pickIds.filter { $0 != save.id.uuidString }
        ids.insert(save.id.uuidString, at: 0)
        Prefs.pickIds = ids
        Prefs.pickDay = rules.dayKey(now)
        pickIds = ids
    }
}

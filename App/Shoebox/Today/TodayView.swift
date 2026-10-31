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

/// Today: one post at a time, full screen, with the same moves as Scales.
/// Swipe up past 100 pt: the next one, and this one comes back when your why says, or tomorrow.
/// Pull down past 160 pt (further, so it is never an accident): into the box, done and kept.
/// A quick tap opens it. The post follows the finger 1:1 for 40 pt, then at half speed, and springs
/// back short of a threshold. Crossing a threshold ticks. Both moves can be undone for 5 seconds.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Save.createdAt) private var all: [Save]

    @State private var pickIds: [String] = Prefs.pickIds
    @State private var showBox = false
    @State private var showAdd = false
    @State private var opened: OpenedPost?
    @State private var toast: Toast?

    // The gesture
    @State private var drag: CGFloat = 0
    @State private var dragStart = Date()
    @State private var dragging = false
    @State private var crossed = 0          // 1 past Next, -1 past Put away
    @State private var fly: CGFloat = 0
    @State private var flyScale: CGFloat = 1
    @State private var flyOpacity: Double = 1
    @State private var busy = false

    private let rules = TodayRules()
    private let actions = SaveActions()
    private let planner = LaterPlanner()

    static let upDistance: CGFloat = 100
    static let downDistance: CGFloat = 160
    static let stripHeight: CGFloat = 92

    private var now: Date { Date() }
    private var queue: [Save] { rules.today(all, ids: pickIds, now: now) }
    private var boxCount: Int { rules.kept(all).count + rules.away(all, now: now).count }
    private var anyKept: Bool { all.contains { $0.deletedAt == nil } }
    private var moreWaiting: [Save] { rules.queue(all, now: now).filter { !pickIds.contains($0.id.uuidString) } }
    private var moving: Bool { drag != 0 || fly != 0 }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack {
                Theme.ground.ignoresSafeArea()

                if let current = queue.first {
                    if moving, let next = queue.dropFirst().first {
                        card(next, geo)
                            .scaleEffect(0.94)
                            .opacity(0.6)
                            .accessibilityHidden(true)
                    }
                    card(current, geo)
                        .scaleEffect(cardScale, anchor: .bottom)
                        .offset(y: resisted(drag) + fly)
                        .opacity(flyOpacity)
                        .id(current.id)
                        .gesture(cardGesture(current, height: height))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens this post")
                        .accessibilityAction(named: "Next one") { goNext(current, height: height) }
                        .accessibilityAction(named: "Put away") { goAway(current, height: height) }
                        .task(id: current.id) { await enrichAhead() }
                    hints
                    topBar(onPhoto: true)
                } else {
                    stopScreen
                    topBar(onPhoto: false)
                }

                strip

                if let toast {
                    toastView(toast)
                }
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
                onClose: { opened = nil },
                onNotNow: { opened = nil; notNow(save) },
                onPutAway: { opened = nil; putAway(save) }
            )
        }
        .sheet(isPresented: $showBox) {
            BoxView(planner: planner, onBringBack: { bringBack($0) })
                .presentationDetents([.large])
                .presentationCornerRadius(Metrics.sheetRadius)
        }
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
    }

    // MARK: Layout

    /// A full-screen post. Square while it rests, rounded while it moves, like a card lifted off the stack.
    private func card(_ save: Save, _ geo: GeometryProxy) -> some View {
        PostCard(save: save, now: now, insets: geo.safeAreaInsets, bottomRoom: Self.stripHeight)
            .ignoresSafeArea()
            .clipShape(RoundedRectangle(cornerRadius: moving ? 44 : 0, style: .continuous))
            .ignoresSafeArea()
    }

    private var cardScale: CGFloat {
        let pull = drag > 0 ? 1 - min(0.06, drag / Self.downDistance * 0.06) : 1
        return pull * flyScale
    }

    private func topBar(onPhoto: Bool) -> some View {
        VStack {
            HStack {
                Button { showAdd = true } label: {
                    Text("+ New")
                        .font(.system(size: 16, weight: .medium))
                        .frame(minWidth: 88, minHeight: Metrics.touchMin, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keep something new")
                Spacer()
                if !queue.isEmpty {
                    Text("\(max(1, pickIds.count - queue.count + 1)) of \(pickIds.count)")
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(onPhoto ? Color.white : Theme.ink)
            .shadow(color: onPhoto ? .black.opacity(0.35) : .clear, radius: 6)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .opacity(drag > 0 ? max(0.35, 1 - drag / Self.downDistance) : 1)
            Spacer()
        }
    }

    /// "Next" and "Put away" fade in as the post moves toward them, bold once it is far enough.
    private var hints: some View {
        let up = max(0, -drag) / Self.upDistance
        let down = max(0, drag) / Self.downDistance
        return VStack {
            hint("Next", progress: up).padding(.top, 64)
            Spacer()
            hint("Put away", progress: down).padding(.bottom, Self.stripHeight + 56)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hint(_ text: String, progress p: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 15, weight: p >= 1 ? .bold : .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 6)
            .opacity(p <= 0 ? 0 : (p >= 1 ? 1 : 0.2 + 0.5 * p))
    }

    /// Your Shoebox, across the bottom. It rises a little as a post is pulled toward it, and its lid
    /// line lifts and turns Nectarine once the post is far enough to drop in. Tap it or pull it up to open the Box.
    private var strip: some View {
        let ready = crossed == -1
        let growth = drag > 0 ? min(40, drag * 0.25) : 0
        return VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                    .fill(Theme.box)
                    .ignoresSafeArea(edges: .bottom)
                Rectangle()
                    .fill(ready ? Theme.lid : Theme.boxLid)
                    .frame(height: ready ? 4 : 3)
                    .shadow(color: ready ? Theme.lid.opacity(0.7) : .clear, radius: 8)
                    .padding(.top, ready ? 6 : 12)
                HStack(alignment: .firstTextBaseline) {
                    Text(ready ? "Let go to put it away" : "Your Shoebox")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(boxCount)")
                        .font(.system(size: 17))
                        .monospacedDigit()
                        .foregroundStyle(Theme.boxQuiet)
                }
                .foregroundStyle(Theme.boxInk)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
            .frame(height: Self.stripHeight + growth)
            .contentShape(Rectangle())
            .onTapGesture { showBox = true }
            .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                if v.translation.height < -40 { showBox = true }
            })
            .animation(.snappy, value: ready)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens everything you kept")
        }
    }

    /// The day's end: a message, not a post, set high, with its choices as rows.
    private var stopScreen: some View {
        let more = moreWaiting
        let head: String
        let sub: String
        if !anyKept {
            head = "Nothing kept yet."
            sub = "Share a page to Shoebox from Safari or any app, or tap New."
        } else if !more.isEmpty {
            head = "That's \(pickIds.count) for today."
            sub = "Keep going as long as you like."
        } else {
            head = "That's all for today."
            sub = nextBackText
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(head)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(sub)
                .font(.system(size: 16))
                .foregroundStyle(Theme.quiet)
            VStack(spacing: 0) {
                if !more.isEmpty { row("Keep going") { keepGoing() } }
                row("Keep something") { showAdd = true }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            .padding(.top, 28)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 150)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\u{203A}").font(.system(size: 22)).foregroundStyle(Theme.quiet)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private var nextBackText: String {
        guard let next = rules.away(all, now: now).first?.returnDate else { return "Everything is put away." }
        let label = planner.label(for: next, now: now)
        return label == "Tomorrow" ? "Next one back tomorrow." : "Next one back \(label)."
    }

    /// Undo: small, at the right above the box, clear of the post and of the thumb's swipe path.
    private func toastView(_ toast: Toast) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    Text(toast.text).opacity(0.8).padding(.leading, 16)
                    Button("Undo") {
                        toast.undo()
                        withAnimation(.snappy) { self.toast = nil }
                        refreshPick()
                    }
                    .fontWeight(.bold)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Metrics.touchMin)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.ground)
                .background(Theme.ink, in: Capsule())
            }
            .padding(.trailing, 16)
            .padding(.bottom, Self.stripHeight + 14)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: The gesture

    private func resisted(_ v: CGFloat) -> CGFloat {
        let a = abs(v)
        let s: CGFloat = v < 0 ? -1 : 1
        return s * (a <= 40 ? a : 40 + (a - 40) * 0.5)
    }

    private func cardGesture(_ current: Save, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !busy else { return }
                if !dragging { dragging = true; dragStart = Date() }
                let dy = v.translation.height
                if abs(dy) < 6 && abs(v.translation.width) < 6 { return }
                drag = dy
                let c = -dy >= Self.upDistance ? 1 : (dy >= Self.downDistance ? -1 : 0)
                if c != crossed {
                    if c != 0 { UISelectionFeedbackGenerator().selectionChanged() }
                    crossed = c
                }
            }
            .onEnded { v in
                guard !busy else { return }
                dragging = false
                crossed = 0
                let dy = v.translation.height
                let moved = abs(dy) >= 6 || abs(v.translation.width) >= 6
                if !moved && Date().timeIntervalSince(dragStart) < 0.35 {
                    drag = 0
                    opened = OpenedPost(save: current)
                    return
                }
                if dy <= -Self.upDistance { goNext(current, height: height) }
                else if dy >= Self.downDistance { goAway(current, height: height) }
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { drag = 0 } }
            }
    }

    /// Flies the post off, then makes the change and brings the next one in.
    private func flyOff(up: Bool, height: CGFloat, then change: @escaping () -> Void) {
        busy = true
        withAnimation(.easeIn(duration: 0.3)) {
            if up {
                fly = -height * 1.1
            } else {
                fly = height * 0.6
                flyScale = 0.9
            }
            flyOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            change()
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                drag = 0; fly = 0; flyScale = 1; flyOpacity = 1
            }
            busy = false
        }
    }

    private func goNext(_ save: Save, height: CGFloat) {
        flyOff(up: true, height: height) { notNow(save) }
    }

    private func goAway(_ save: Save, height: CGFloat) {
        // Set down firmly, then it fades away.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        flyOff(up: false, height: height) { putAway(save) }
    }

    // MARK: Actions

    private func perform(_ text: String, on save: Save, _ change: (Save) -> Void) {
        let snapshot = SaveSnapshot(save)
        change(save)
        try? context.save()
        let new = Toast(text: text, undo: { snapshot.restore(save); try? context.save() })
        withAnimation(.snappy) { toast = new }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if toast?.id == new.id { withAnimation { toast = nil } }
        }
    }

    /// Not now: back when your why says (a weekday, the weekend, tonight), else tomorrow.
    /// Dated posts keep their own schedule of reminders.
    private func notNow(_ save: Save) {
        if save.eventDate == nil, let when = planner.match(words: save.note, now: now) {
            let label = when.label == "Tomorrow" ? "tomorrow" : when.label
            perform("Back \(label)", on: save) { actions.later($0, until: when.date, now: now) }
        } else {
            perform(save.eventDate == nil ? "Back tomorrow" : "Back before the date", on: save) { actions.pass($0, now: now) }
        }
    }

    /// Into the box: done, kept and searchable.
    private func putAway(_ save: Save) {
        perform("Put away", on: save) { actions.done($0, now: now) }
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

    /// Past the day's pile: the next few come out.
    private func keepGoing() {
        let ids = pickIds + moreWaiting.prefix(Prefs.perDay).map(\.id.uuidString)
        Prefs.pickIds = ids
        Prefs.pickDay = rules.dayKey(now)
        pickIds = ids
        UISelectionFeedbackGenerator().selectionChanged()
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
        case "up": drag = -110; crossed = 1
        case "away": drag = 170; crossed = -1
        case "opened": if let first = queue.first { opened = OpenedPost(save: first) }
        case "box", "settings": showBox = true
        case "add": showAdd = true
        default: break
        }
        #endif
    }
}

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
    @State private var bump = 0

    private let rules = TodayRules()
    private let actions = SaveActions()
    private let planner = LaterPlanner()

    static let upDistance: CGFloat = 100
    static let downDistance: CGFloat = 160
    static let stripHeight: CGFloat = 110

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

    /// "Next" fades in as the post moves up, bold once it is far enough. Pulling down, the box itself
    /// says "Let go to put it away", so there is no second hint over the post.
    private var hints: some View {
        let up = max(0, -drag) / Self.upDistance
        return VStack {
            hint("Next", progress: up).padding(.top, 64)
            Spacer()
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

    /// Your Shoebox, across the bottom: a Wheat box with its Nectarine lid on top, like the logo.
    /// The lid lifts and tips open once a post is far enough to drop in, and the whole box rattles
    /// when a post is flicked away or dropped into it. Tap it or pull it up to open the Box.
    private var strip: some View {
        let ready = crossed == -1
        let growth = drag > 0 ? min(40, drag * 0.25) : 0
        return VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .top) {
                // Smoked glass: the photo blurs through, so the box belongs to every post.
                Color.clear
                    .glassEffect(.regular.tint(Theme.onyx.opacity(0.55)), in: Rectangle())
                    .padding(.top, 16)
                    .ignoresSafeArea(edges: .bottom)
                HStack(alignment: .center, spacing: 12) {
                    AppLogo(size: 30, tile: false)
                    Text(ready ? "Let go to put it away" : "Your Shoebox")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(boxCount)")
                        .font(.system(size: 17))
                        .monospacedDigit()
                        .foregroundStyle(Theme.boxBody.opacity(0.65))
                }
                .foregroundStyle(Theme.boxBody)
                .padding(.horizontal, 24)
                .padding(.top, 50)
                lid(ready: ready)
            }
            .frame(height: Self.stripHeight + growth)
            .contentShape(Rectangle())
            .onTapGesture { showBox = true }
            .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                if v.translation.height < -40 { showBox = true }
            })
            .keyframeAnimator(initialValue: BoxShake(), trigger: bump) { content, v in
                content.offset(x: v.dx)
            } keyframes: { _ in
                KeyframeTrack(\.dx) {
                    LinearKeyframe(0, duration: 0.001)
                    CubicKeyframe(-4, duration: 0.04)
                    CubicKeyframe(4, duration: 0.06)
                    CubicKeyframe(-3, duration: 0.06)
                    CubicKeyframe(2, duration: 0.06)
                    CubicKeyframe(-1, duration: 0.06)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
            .animation(.snappy, value: ready)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens everything you kept")
        }
    }

    /// The Nectarine lid: hinged at the left, resting almost flat, tipped open when a post is ready to drop in.
    /// Bumped, it knocks against the box.
    private func lid(ready: Bool) -> some View {
        // A shoebox top: lit along its top edge, a slightly deeper lip where it folds down over
        // the sides, and a shadow cast down onto the box so it sits over it.
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(stops: [.init(color: Theme.lid, location: 0),
                                         .init(color: Theme.lid, location: 0.72),
                                         .init(color: Theme.lidLip, location: 0.78),
                                         .init(color: Theme.lidLip, location: 1)],
                                 startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .white.opacity(0.55), radius: 1, x: 0, y: 1.5)))
            .frame(height: 34)
            .padding(.horizontal, -8)
            .shadow(color: .black.opacity(ready ? 0 : 0.35), radius: 2.5, y: 3)
            .shadow(color: ready ? Theme.lid.opacity(0.65) : .black.opacity(0.32), radius: ready ? 12 : 10, y: ready ? 0 : 9)
            .rotationEffect(.degrees(ready ? -4 : -0.6), anchor: .leading)
            .offset(y: ready ? -6 : 0)
            .keyframeAnimator(initialValue: BoxShake(), trigger: bump) { content, v in
                content.rotationEffect(.degrees(v.angle), anchor: .leading).offset(y: v.lift)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: 0.001)
                    CubicKeyframe(-5, duration: 0.05)
                    CubicKeyframe(3, duration: 0.07)
                    CubicKeyframe(-3.5, duration: 0.07)
                    CubicKeyframe(2, duration: 0.07)
                    CubicKeyframe(-1, duration: 0.06)
                    CubicKeyframe(0, duration: 0.08)
                }
                KeyframeTrack(\.lift) {
                    LinearKeyframe(0, duration: 0.001)
                    CubicKeyframe(-5, duration: 0.05)
                    CubicKeyframe(0, duration: 0.07)
                    CubicKeyframe(-3, duration: 0.07)
                    CubicKeyframe(0, duration: 0.07)
                    CubicKeyframe(-1, duration: 0.06)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
    }

    /// Rattle the box: the lid knocks and the haptics rustle.
    private func rattleBox(strong: Bool, after delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            bump += 1
            BoxRattle.play(strong: strong)
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
        rattleBox(strong: false)
        flyOff(up: true, height: height) { notNow(save) }
    }

    private func goAway(_ save: Save, height: CGFloat) {
        // Set down firmly, then it fades away.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        rattleBox(strong: true, after: 0.18)
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
        backfillDates()
        if rules.retirePast(all, now: now) > 0 { try? context.save() }
        let ids = rules.pick(all, now: now, previousDay: Prefs.pickDay, previousIds: Prefs.pickIds, perDay: Prefs.perDay)
        Prefs.pickDay = rules.dayKey(now)
        Prefs.pickIds = ids
        if ids != pickIds { pickIds = ids }
    }

    /// Fills in link previews for the post on screen and the next two, then a stock picture
    /// for any of them that still has none.
    private func enrichAhead() async {
        for s in queue.prefix(3) where s.enrichedAt == nil && s.url != nil {
            await Relay.enrich(s)
        }
        try? context.save()
        for s in queue.prefix(3) where s.imageData == nil {
            await StockPhoto.fill(s)
        }
        try? context.save()
    }

    /// Once, for the saves kept before dates were read for every save: read the date each one names.
    /// Reading is relative to the day it was kept, so "October 30" in a post kept on October 26 is this year's.
    private func backfillDates() {
        guard !Prefs.datesBackfilled else { return }
        for s in all where s.deletedAt == nil && s.status != .kept && s.eventDate == nil {
            // Read as of today, so a date already gone by is never taken, and nothing is moved to Kept unseen.
            guard DateReader.apply(to: s, asOf: now), let event = s.eventDate else { continue }
            if s.status == .away, let due = s.returnDate,
               let first = actions.reminders(for: event).first(where: { $0 > now }), first < due {
                s.returnDate = first
            }
        }
        try? context.save()
        Prefs.datesBackfilled = true
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

/// The box's shake, played as keyframes.
struct BoxShake {
    var dx: CGFloat = 0
    var angle: Double = 0
    var lift: CGFloat = 0
}

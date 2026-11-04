import SwiftData
import SwiftUI
import UIKit

struct Toast: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void
}

/// A post being read. Wraps the save so the full-screen cover has a stable identity: the same post opened twice
/// (a double tap) is the same item, so SwiftUI does not present a second cover over the first.
struct OpenedPost: Identifiable {
    var id: UUID { save.id }
    let save: Save
}

/// Today: one post at a time, full screen, with the same moves as Scales.
/// Swipe up past 100 pt: the next one, and this one comes back when your why says, or tomorrow.
/// Pull down past 160 pt (further, so it is never an accident): Put away, done and kept.
/// A quick tap opens it. The post follows the finger 1:1 for 40 pt, then at half speed, and springs
/// back short of a threshold. Crossing a threshold ticks. Both moves can be undone for 5 seconds.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Save.createdAt) private var all: [Save]

    @State private var pickIds: [String] = Prefs.pickIds
    /// How far the Shoebox sheet is out from behind the box: 0 hidden, 1 fully open. It follows the thumb.
    @State private var pull = BoxPull()
    @GestureState private var pulling = false
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var opened: OpenedPost?
    @State private var toast: Toast?
    /// "Go through your Shoebox": the posts brought out after the day's stack, and the ones already gone through.
    @State private var browseIds: [UUID] = []
    @State private var browsedIds: Set<UUID> = []

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
    @State private var backfilling = false
    /// The next post rises out of the lid after a flick up: 1 while it waits down at the lid, 0 once risen.
    @State private var rise: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rules = TodayRules()
    private let actions = SaveActions()
    private let planner = LaterPlanner()

    static let upDistance: CGFloat = 100
    static let downDistance: CGFloat = 160
    static let stripHeight: CGFloat = 120
    /// How far the lid sits below the top of the strip, and how far above the Shoebox sheet's top edge it rides.
    static let lidTop: CGFloat = 8
    static let sheetLidRise: CGFloat = 34

    private var now: Date { Date() }
    private var queue: [Save] {
        let today = rules.today(all, ids: pickIds, now: now)
        guard !browseIds.isEmpty else { return today }
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let extra = browseIds.compactMap { byId[$0] }.filter { $0.deletedAt == nil && $0.status != .kept }
        return today + extra
    }
    /// Posts in the Shoebox that are not on Today now and not yet gone through: what "Go through your Shoebox" brings out.
    private var browsable: [Save] {
        let onToday = Set(rules.today(all, ids: pickIds, now: now).map(\.id))
        return rules.library(all, now: now).filter { !onToday.contains($0.id) && !browsedIds.contains($0.id) }
    }
    /// Everything in the Shoebox that is not put away.
    private var boxCount: Int { rules.library(all, now: now).count }
    private var anyKept: Bool { all.contains { $0.deletedAt == nil } }
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
                        .scaleEffect(cardScale * (reduceMotion ? 1 : 1 - 0.08 * rise), anchor: .bottom)
                        .offset(y: resisted(drag) + fly + (reduceMotion ? 0 : 180 * rise))
                        .opacity(flyOpacity * (1 - Double(rise)))
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
                    newLow
                }

                // The Shoebox slides out from behind the box, at the pace of the thumb.
                if pull.mounted {
                    // A tap above the sheet does nothing (a thumb reaching for Settings lands here); a drag closes it.
                    BoxDim(pull: pull)
                        .gesture(boxPull(height: height, top: geo.safeAreaInsets.top))
                    boxSheet(height: height, top: geo.safeAreaInsets.top)
                }

                glass
                    .modifier(BoxStripFade(pull: pull))

                strip
                    .modifier(BoxStripFade(pull: pull))
                    .gesture(boxPull(height: height, top: geo.safeAreaInsets.top))

                if let toast {
                    toastView(toast, aboveNew: queue.isEmpty)
                }
            }
        }
        .onAppear {
            refreshPick()
            showScreenForScreenshots()
            // Build the Shoebox sheet once, out of sight, so the first pull has nothing to build.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pull.mounted = true }
            Task { try? await Task.sleep(for: .seconds(3)); await backfillPictures() }
        }
        .onChange(of: pulling) { _, now in
            // A drag the system cancelled (an edge swipe, a call) never ends: settle where it stopped.
            if !now && pull.dragging {
                pull.dragging = false
                settleBox(open: pull.progress > 0.5)
            }
        }
        .onChange(of: phase) { _, p in if p == .active { refreshPick(); Task { await backfillPictures() } } }
        .onChange(of: all.count) { _, _ in refreshPick() }
        .fullScreenCover(item: $opened) { item in
            let save = item.save
            OpenedView(
                save: save,
                onClose: { opened = nil },
                onNotNow: { opened = nil; notNow(save) },
                onPutAway: { opened = nil; putAway(save) },
                onBringBack: { opened = nil; bringBack(save) },
                onDelete: { opened = nil; deleteSave(save) }
            )
        }
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: The Shoebox sheet

    private static let boxSpring = Animation.spring(response: 0.32, dampingFraction: 0.9)

    /// Where the top of the sheet sits: hidden behind the box, and fully open just under the status bar.
    private func boxTops(_ height: CGFloat, _ top: CGFloat) -> (closed: CGFloat, open: CGFloat) {
        (height - Self.stripHeight + Self.lidTop + Self.sheetLidRise, top + 48)
    }

    private func boxSheet(height: CGFloat, top: CGFloat) -> some View {
        let tops = boxTops(height, top)
        let drag = boxPull(height: height, top: top)
        // On the header the drag must travel further before it takes over, so a tap on Today or Settings
        // that wobbles a few points is still a tap.
        let headerDrag = boxPull(height: height, top: top, minimum: 30)
        return ZStack(alignment: .top) {
            GlassSheet {
                VStack(spacing: 0) {
                    // Room for the open lid along the top edge. The whole top of the Shoebox pulls too.
                    Color.clear.frame(height: 12)
                    BoxView(planner: planner, pull: pull, otherPostOpen: opened != nil, onClose: { closeBox() }, onBringBack: { bringBack($0) },
                            onBrowse: { closeBox(); startBrowsing() }, onSettings: { showSettings = true },
                            onHandOff: { if toast == nil { show($0) } },
                            pullGesture: AnyGesture(headerDrag.map { _ in () }))
                }
                .frame(height: height - tops.open)
            }
            .frame(height: height - tops.open)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetRadius, topTrailingRadius: Metrics.sheetRadius, style: .continuous))

            // The open lid along the sheet's top edge, where a grab handle would be. Pull it down to close; a tap does nothing.
            BoxSheetLid(pull: pull)
                .padding(.horizontal, BoxLid.inset)
                .offset(y: -Self.sheetLidRise)
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(BoxSheetFade(pull: pull))
        .modifier(BoxSheetOffset(pull: pull, closed: tops.closed, open: tops.open))
        .ignoresSafeArea()
    }

    /// One drag opens and closes the sheet: it follows the thumb one to one, and on release it settles open
    /// or closed by where it is and how fast you were going. Measured on the screen, not on the sheet, because
    /// the sheet moves under the finger and its own measure would shrink as it follows.
    private func boxPull(height: CGFloat, top: CGFloat, minimum: CGFloat = 4) -> some Gesture {
        let tops = boxTops(height, top)
        let travel = max(1, tops.closed - tops.open)
        return DragGesture(minimumDistance: minimum, coordinateSpace: .global)
            .updating($pulling) { _, state, _ in state = true }
            .onChanged { v in
                if !pull.dragging { pull.dragging = true; pull.start = pull.progress; pull.mounted = true }
                pull.progress = min(1, max(0, pull.start - v.translation.height / travel))
            }
            .onEnded { v in
                pull.dragging = false
                let predicted = pull.start - v.predictedEndTranslation.height / travel
                settleBox(open: predicted > 0.5)
            }
    }

    private func openBox() {
        pull.mounted = true
        settleBox(open: true)
    }

    private func closeBox() { settleBox(open: false) }

    private func settleBox(open: Bool) {
        if open { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } else { pull.closedTick += 1 }
        withAnimation(Self.boxSpring) { pull.progress = open ? 1 : 0 }
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
                if !queue.isEmpty && browseIds.isEmpty {
                    Text("\(max(1, pickIds.count - queue.count + 1)) of \(pickIds.count)")
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(onPhoto ? Theme.onPhoto : Theme.ink)
            .shadow(color: onPhoto ? Theme.shade.opacity(0.35) : .clear, radius: 6)
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
            .foregroundStyle(Theme.onPhoto)
            .shadow(color: Theme.shade.opacity(0.45), radius: 6)
            .opacity(p <= 0 ? 0 : (p >= 1 ? 1 : 0.2 + 0.5 * p))
    }

    /// The glass the box rises out of (SPEC 2.2): the lower 360 pt of the screen, clear at the top and nearly solid at the
    /// bottom edge. It shakes with the lid.
    private var glass: some View {
        VStack(spacing: 0) {
            Spacer()
            BoxGlass()
                .padding(.horizontal, -10)
                .keyframeAnimator(initialValue: BoxShake(), trigger: reduceMotion ? 0 : bump) { content, v in
                    content.offset(x: v.dx)
                } keyframes: { _ in boxShakeKeyframes }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    /// Your Shoebox, across the bottom: the Sunflower lid on the glass, with the count under it. The lid leans a little
    /// when a post is pulled down, and tips open with a glow once it is far enough to drop in. The glass and lid rattle
    /// when a post is flicked away or dropped in. Tap the box or pull it up to open the Shoebox.
    private var strip: some View {
        let ready = crossed == -1
        let leaning = drag > 40 && !ready
        return VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .top) {
                HStack(alignment: .center, spacing: 12) {
                    // Bare: the lid says what it is. Only the drop hint speaks, and the count.
                    Text(ready ? "Let go to put it away" : "")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.lid)
                    Spacer()
                    Text("\(boxCount)")
                        .font(.system(size: 17))
                        .monospacedDigit()
                        .foregroundStyle(Theme.boxText.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .padding(.top, Self.lidTop + BoxLid.height + 14)
                .animation(.snappy, value: ready)
                BoxLid(extraAngle: ready ? 5 : (leaning ? 1.5 : 0), glowing: ready)
                    .padding(.horizontal, BoxLid.inset)
                    .padding(.top, Self.lidTop)
                    .keyframeAnimator(initialValue: BoxShake(), trigger: reduceMotion ? 0 : bump) { content, v in
                        content.rotationEffect(.degrees(v.angle), anchor: .leading).offset(y: v.lift)
                    } keyframes: { _ in lidShakeKeyframes }
                    // The Shoebox sheet carries its own lid once it starts to move.
                    .modifier(BoxLidHide(pull: pull))
            }
            .frame(height: Self.stripHeight)
            .contentShape(Rectangle())
            .onTapGesture { openBox() }
            .keyframeAnimator(initialValue: BoxShake(), trigger: reduceMotion ? 0 : bump) { content, v in
                content.offset(x: v.dx)
            } keyframes: { _ in boxShakeKeyframes }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Your Shoebox, \(boxCount)")
            .accessibilityHint("Opens everything you are not done with")
        }
    }

    @KeyframesBuilder<BoxShake>
    private var boxShakeKeyframes: some Keyframes<BoxShake> {
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

    @KeyframesBuilder<BoxShake>
    private var lidShakeKeyframes: some Keyframes<BoxShake> {
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

    /// Rattle the box: the lid knocks and the haptics rustle.
    private func rattleBox(strong: Bool, after delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            bump += 1
            BoxRattle.play(strong: strong)
        }
    }

    /// The day's end: who we are at the top (the logo, the name and the line), then a message, not a post, with one
    /// choice: keep going through your Shoebox. + New sits low on the right, under the thumb (`newLow`).
    private var stopScreen: some View {
        let more = browsable
        let head: String
        let sub: String
        if !anyKept {
            head = "Nothing kept yet."
            sub = "Share a page to Shoebox from Safari or any app, or tap + New below."
        } else if !pickIds.isEmpty && !more.isEmpty {
            head = "That's \(pickIds.count) for today."
            sub = "Got time? Go through your Shoebox and act on what you like."
        } else if !more.isEmpty {
            head = "That's all for today."
            sub = "Got time? Go through your Shoebox and act on what you like."
        } else {
            head = "That's all for today."
            sub = nextBackText
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                AppLogo(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shoebox")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Keep it. It comes back to you.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.quiet)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shoebox. Keep it. It comes back to you.")
            .padding(.bottom, 88)
            Text(head)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(sub)
                .font(.system(size: 16))
                .foregroundStyle(Theme.quiet)
            if !more.isEmpty {
                VStack(spacing: 0) {
                    row("Go through your Shoebox") { startBrowsing() }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .padding(.top, 28)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// + New on the day's end screen: low on the right, just above the box, where the right thumb rests.
    /// (On a post it stays at the top, clear of the flick and the words.)
    private var newLow: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { showAdd = true } label: {
                    Text("+ New")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 88, minHeight: Metrics.touchMin, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keep something new")
            }
            .padding(.trailing, 24)
            .padding(.bottom, Self.stripHeight + 12)
        }
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
    private func toastView(_ toast: Toast, aboveNew: Bool = false) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                UndoPill(text: toast.text) {
                    toast.undo()
                    withAnimation(.snappy) { self.toast = nil }
                    refreshPick()
                }
            }
            .padding(.trailing, 16)
            // On the day's end screen + New sits here, so Undo rises above it.
            .padding(.bottom, Self.stripHeight + 14 + (aboveNew ? Metrics.touchMin + 8 : 0))
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
                // The Shoebox is out over the post: the post takes no moves until it is closed.
                guard !busy, pull.progress < 0.02 else { return }
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
                if pull.progress >= 0.02 && !dragging { return }
                dragging = false
                crossed = 0
                let dy = v.translation.height
                let moved = abs(dy) >= 6 || abs(v.translation.width) >= 6
                if !moved && Date().timeIntervalSince(dragStart) < 0.35 {
                    drag = 0
                    if opened == nil { opened = OpenedPost(save: current) }
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
                // Up: the next post waits down at the lid, then rises out of it. Away: it comes in as before.
                rise = up ? 1 : 0
            }
            busy = false
            if up {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.82)) { rise = 0 }
                }
            }
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
        perform(on: save) { change($0); return text }
    }

    /// Makes the change, keeps it, and shows Undo for 5 seconds. The change returns the words for the message.
    private func perform(on save: Save, _ change: (Save) -> String) {
        if let i = browseIds.firstIndex(of: save.id) {
            browseIds.remove(at: i)
            browsedIds.insert(save.id)
        }
        let snapshot = SaveSnapshot(save)
        let text = change(save)
        try? context.save()
        show(Toast(text: text, undo: { snapshot.restore(save); try? context.save() }))
    }

    /// Shows Undo for 5 seconds.
    private func show(_ new: Toast) {
        withAnimation(.snappy) { toast = new }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if toast?.id == new.id { withAnimation { toast = nil } }
        }
    }

    /// Next: back when your why says (a weekday, the weekend, tonight), else tomorrow.
    /// Dated posts keep their own schedule of reminders.
    private func notNow(_ save: Save) {
        perform(on: save) { actions.next($0, planner: planner, now: now) }
    }

    /// Delete: gone from every list, kept in backups, and Undo for 5 seconds.
    private func deleteSave(_ save: Save) {
        perform("Deleted", on: save) { actions.letGo($0, now: now) }
    }

    /// Into the box: done, kept and searchable.
    private func putAway(_ save: Save) {
        perform("Put away", on: save) { actions.done($0, now: now) }
    }

    private func bringBack(_ save: Save) {
        closeBox()
        perform("Back on Today", on: save) { actions.bringBack($0, now: now) }
        var ids = Prefs.pickIds.filter { $0 != save.id.uuidString }
        ids.insert(save.id.uuidString, at: 0)
        Prefs.pickIds = ids
        Prefs.pickDay = rules.dayKey(now)
        pickIds = ids
    }

    /// Past the day's stack: everything else in the Shoebox comes out one at a time, with the same moves as Today.
    /// What is due soonest comes first. Each is gone through once.
    private func startBrowsing() {
        browseIds = browsable.map(\.id)
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

    /// Posts that sit in the Shoebox never reach the front of Today, so they never got a picture. A few at a time, newest
    /// first, each opening of the app: the link's own picture, then a stock one. A miss is tried again tomorrow, not now.
    private func backfillPictures() async {
        guard !backfilling else { return }
        backfilling = true
        defer { backfilling = false }
        if StockPhoto.forgetOldTries(all) > 0 { try? context.save() }
        let waiting = rules.library(all, now: now)
            .filter { s in
                s.imageData == nil && s.kind != .photo && !StockPhoto.recentlyTried(s, now: now)
            }
            // Never-tried first, so posts the rules skip (health, money) do not hold the line every day.
            .sorted { ($0.stockTriedAt != nil ? 1 : 0, -$0.createdAt.timeIntervalSince1970) < ($1.stockTriedAt != nil ? 1 : 0, -$1.createdAt.timeIntervalSince1970) }
            .prefix(10)
        if !waiting.isEmpty { Prefs.pictureLog = [:] }
        for s in waiting {
            if Task.isCancelled { break }
            if s.enrichedAt == nil, s.url != nil { await Relay.enrich(s) }
            if s.imageData != nil { StockPhoto.record(.found); continue }
            let outcome = await StockPhoto.fill(s)
            StockPhoto.record(outcome)
            // Pixabay asked us to slow down: the rest wait for the next opening.
            if outcome == .serverBusy { break }
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
        case "opened": if let first = queue.first, opened == nil { opened = OpenedPost(save: first) }
        case "box": pull.mounted = true; pull.progress = 1
        case "settings": pull.mounted = true; pull.progress = 1; showSettings = true
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

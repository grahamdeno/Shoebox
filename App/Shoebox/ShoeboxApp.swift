import SwiftData
import SwiftUI

@main
struct ShoeboxApp: App {
    @State private var container: ModelContainer?
    private let demo: Bool

    init() {
        #if DEBUG
        let demo = UserDefaults.standard.bool(forKey: "demo")
        #else
        let demo = false
        #endif
        self.demo = demo
        if !demo { Diagnostics.shared.start() }
        // A store that will not open shows a recovery screen, never a crash.
        var opened: ModelContainer?
        #if DEBUG
        // The UX audit's time replay keeps its store on disk between launches (`-replay YES`), apart from the real one.
        if demo && UserDefaults.standard.bool(forKey: "replay") { opened = try? Store.make(at: SampleData.replayStore()) }
        #endif
        if opened == nil { opened = try? Store.make(inMemory: demo) }
        _container = State(initialValue: opened)
        #if DEBUG
        if demo, let opened {
            SampleData.seed(opened.mainContext)
            let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
            Prefs.onboarded = !["welcome", "share", "time", "learn"].contains(screen)
            Prefs.pickDay = nil
            if Prefs.mailFor.isEmpty { Prefs.mailFor = "Sam, 7th grade, band" }
            // Colors and light or dark start the same every demo launch (`-colors stone` for Stone), so one run's
            // Settings taps never carry into the next.
            let colors = UserDefaults.standard.string(forKey: "colors") ?? "pistachio"
            AppGroup.defaults.set(colors, forKey: "colors")
            AppGroup.defaults.set(colors, forKey: "colorsApplied")
            AppGroup.defaults.set(0, forKey: "appearance")
            // The daily limit starts at its default every demo launch, so a journey that changes it never changes the next.
            Prefs.perDay = Prefs.defaultPerDay
            // Stock pictures on, except in the audit's no-photos run.
            Prefs.stockPictures = (UserDefaults.standard.string(forKey: "dataset") ?? "") != "nophotos"
            // Plus in the audit (`-plusState store` or `beta`): the store's offer after the first week, or a tester's
            // free address. Never touches StoreKit's real state or the relay.
            switch UserDefaults.standard.string(forKey: "plusState") ?? "" {
            case "store": Prefs.firstOpened = Clock.now - 8 * 86_400; Plus.demo(sandbox: false)
            case "beta": Plus.demo(sandbox: true)
            default: Prefs.firstOpened = nil
            }
            if screen == "clear" { SampleData.clearToday(opened.mainContext) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .appearance()
                    .tint(Theme.accent)
                    .modelContainer(container)
            } else {
                StoreProblemView { container = try? Store.make(inMemory: demo) }
                    .appearance()
                    .tint(Theme.accent)
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var onboarded = Prefs.onboarded

    var body: some View {
        Group {
            if onboarded {
                TodayView()
            } else {
                Onboarding { withAnimation(.snappy) { onboarded = true } }
            }
        }
        .tint(Theme.ink)
        .task { await opened() }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: Task { await opened() }
            case .background: closed()
            default: break
            }
        }
    }

    private func opened() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") { return }
        #endif
        // The first run, then the mailbox secret into the Keychain (before anything reads it), then a Delete everything
        // that has not finished: the relay is asked again on every launch and every return to the app.
        Plus.noteFirstOpen()
        // Not awaited: the store check must never hold up the collection.
        Task { await Plus.checkStore() }
        MailboxKeys.migrate()
        Plus.startListening()
        await Backups.resolveCloud()
        _ = await Backups.autoImport(context)
        await Inbox.finishPendingDelete()
        await Inbox.collect(context)
        await Notifier.schedule(context)
    }

    private func closed() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") { return }
        #endif
        try? context.save()
        Backups.dailyBackup(context)
        Task { await Notifier.schedule(context) }
        Task { await Inbox.finishPendingDelete() }
    }
}

/// Light, dark or follow the phone, from Settings. Read from the App Group so it
/// changes the moment it is tapped.
private struct AppearanceModifier: ViewModifier {
    @AppStorage("appearance", store: AppGroup.defaults) private var appearance = 0
    /// Pistachio or Stone, as applied when Settings last closed. The colors read the choice each time they are drawn;
    /// changing this redraws everything. It follows the choice only once Settings is closed, so the redraw (which starts
    /// Today fresh) never happens under an open sheet.
    @AppStorage("colorsApplied", store: AppGroup.defaults) private var colors = "pistachio"

    func body(content: Content) -> some View {
        content
            .id(colors)
            // Text grows with the person's text size up to the second accessibility size; past that a full-screen post
            // and its panel no longer fit a phone.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
    }
}

extension View {
    func appearance() -> some View { modifier(AppearanceModifier()) }
}

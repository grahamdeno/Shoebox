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
        let opened = try? Store.make(inMemory: demo)
        _container = State(initialValue: opened)
        #if DEBUG
        if demo, let opened {
            SampleData.seed(opened.mainContext)
            let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
            Prefs.onboarded = !["welcome", "share", "time", "learn"].contains(screen)
            Prefs.pickDay = nil
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
        await Backups.resolveCloud()
        _ = await Backups.autoImport(context)
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
    }
}

/// Light, dark or follow the phone, from Settings. Read from the App Group so it
/// changes the moment it is tapped.
private struct AppearanceModifier: ViewModifier {
    @AppStorage("appearance", store: AppGroup.defaults) private var appearance = 0

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
    }
}

extension View {
    func appearance() -> some View { modifier(AppearanceModifier()) }
}

import SwiftData
import SwiftUI

@main
struct ShoeboxApp: App {
    let container: ModelContainer

    init() {
        #if DEBUG
        let demo = UserDefaults.standard.bool(forKey: "demo")
        #else
        let demo = false
        #endif
        do {
            container = try Store.make(inMemory: demo)
        } catch {
            fatalError("Could not open the Shoebox store: \(error)")
        }
        #if DEBUG
        if demo {
            SampleData.seed(container.mainContext)
            let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
            Prefs.onboarded = !["welcome", "share", "time", "learn"].contains(screen)
            Prefs.pickDay = nil
            if screen == "clear" { SampleData.clearToday(container.mainContext) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appearance()
        }
        .modelContainer(container)
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

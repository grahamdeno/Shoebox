import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import ShoeboxCore

@main
struct ShoeboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(StoreBox.container)
                .themed(model.roles)
                .onOpenURL { model.open($0) }
                .onContinueUserActivity("com.apple.corespotlightitem") { a in
                    if let id = a.userInfo?["kCSSearchableItemActivityIdentifier"] as? String, let u = UUID(uuidString: id) { model.showing = u }
                }
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await model.refresh() } }
            if p == .background { Background.schedule() }
        }
        .backgroundTask(.appRefresh(Background.id)) {
            await Engine.refresh()
            await Background.scheduleAsync()
        }
    }
}

/// App-wide state: the palette, what's open, and the refresh after any change.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    var roles = Theme.roles
    var path: [Route] = []
    var capturing = false
    var searchText = ""

    enum Route: Hashable {
        case save(UUID)
        case everything(EverythingView.Filter, String)
    }

    /// Opens a save on top of wherever you are.
    var showing: UUID? {
        get { nil }
        set { if let id = newValue { path.append(.save(id)) } }
    }

    /// Opens Everything kept, with the question asked.
    var searching: Bool {
        get { false }
        set { if newValue { path.append(.everything(.all, searchText)) } }
    }
    var importReport: String?
    var toast: Toast?

    struct Toast: Equatable { var text: String; var undo: UUID? }

    func refresh() async {
        roles = Theme.roles
        if StoreBox.demo { return }
        await Inbox.collect(keeper: .shared())
        await Screenshots.check(keeper: .shared())
        await Engine.refresh()
    }

    func open(_ url: URL) {
        // shoebox://save/<id>, shoebox://new, shoebox://search
        guard url.scheme == "shoebox" else { return }
        switch url.host() {
        case "save": showing = UUID(uuidString: url.lastPathComponent)
        case "new": capturing = true
        case "search": searching = true
        default: break
        }
    }

    func setPalette(_ p: Palette) {
        Prefs.update { $0.palette = p.rawValue }
        roles = ColorRoles.roles(for: p)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Answers from the Lock Screen and the expanded notification. Actions don't open the app (rule 4).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        nonisolated(unsafe) let payload = info
        await MainActor.run {
            if action == UNNotificationDefaultActionIdentifier, let id = (payload["saveId"] as? String).flatMap(UUID.init(uuidString:)) {
                (UIApplication.shared.delegate as? AppDelegate)?.openSave(id)
            }
        }
        await Engine.handle(action: action, userInfo: payload)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    @MainActor func openSave(_ id: UUID) { AppModel.shared.showing = id }
}

enum Background {
    static let id = "com.grahamdeno.shoebox.plan"

    /// Wake shortly before the next Issue so it is composed from the latest plan.
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = nextWake()
        try? BGTaskScheduler.shared.submit(r)
    }

    static func scheduleAsync() async { schedule() }

    static func nextWake(now: Date = .now, cal: Calendar = .current) -> Date {
        let p = Prefs.load()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let day = cal.isDateInWeekend(tomorrow) ? p.weekendIssue : p.weekdayIssue
        let issue = day.date(on: tomorrow, calendar: cal)
        return min(now.addingTimeInterval(4 * 3600), issue.addingTimeInterval(-3600))
    }
}

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
            container = try ModelContainer(for: Save.self, configurations: ModelConfiguration(isStoredInMemoryOnly: demo))
        } catch {
            fatalError("Could not open the Shoebox store: \(error)")
        }
        #if DEBUG
        if demo { SampleData.seedIfEmpty(container.mainContext) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(container)
    }
}

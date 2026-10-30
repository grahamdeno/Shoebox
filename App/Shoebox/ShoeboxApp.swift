import SwiftData
import SwiftUI

@main
struct ShoeboxApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Save.self)
        } catch {
            fatalError("Could not open the Shoebox store: \(error)")
        }
        #if DEBUG
        SampleData.seedIfEmpty(container.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(container)
    }
}

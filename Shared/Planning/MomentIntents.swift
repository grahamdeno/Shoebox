import AppIntents
import Foundation
import ShoeboxCore

/// Buttons on the Live Activity and widgets. They run in the app's process, without opening it.
struct MomentDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done"
    static let isDiscoverable = false
    @Parameter(title: "Save") var saveId: String
    init() {}
    init(saveId: String) { self.saveId = saveId }

    @MainActor
    func perform() async throws -> some IntentResult {
        let k = Keeper.shared()
        if let id = UUID(uuidString: saveId), let s = k.save(id: id) { k.done(s, surface: "liveActivity"); await LiveMoments.end(saveId: id) }
        await Engine.refresh(k)
        return .result()
    }
}

struct MomentLaterIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Later"
    static let isDiscoverable = false
    @Parameter(title: "Save") var saveId: String
    init() {}
    init(saveId: String) { self.saveId = saveId }

    @MainActor
    func perform() async throws -> some IntentResult {
        let k = Keeper.shared()
        if let id = UUID(uuidString: saveId), let s = k.save(id: id) {
            k.later(s, .youChoose, events: CalendarReader.upcoming(), surface: "liveActivity"); await LiveMoments.end(saveId: id)
        }
        await Engine.refresh(k)
        return .result()
    }
}

struct MomentDropIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Drop"
    static let isDiscoverable = false
    @Parameter(title: "Save") var saveId: String
    init() {}
    init(saveId: String) { self.saveId = saveId }

    @MainActor
    func perform() async throws -> some IntentResult {
        let k = Keeper.shared()
        if let id = UUID(uuidString: saveId), let s = k.save(id: id) { k.drop(s, surface: "liveActivity"); await LiveMoments.end(saveId: id) }
        await Engine.refresh(k)
        return .result()
    }
}

import AppIntents
import SwiftData
import UIKit
import ShoeboxCore

/// Moment 4: hold the Action Button, say why. Captures what's on the clipboard or a note, with a spoken reason.
/// [Check] Reading "what's on screen" from Safari needs the page passed by Shortcuts; on its own the intent keeps
/// the copied link or text, or your words as a note.
struct KeepIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep in Shoebox"
    static let description = IntentDescription("Keep something with your reason. It comes back when it's useful.")
    static let openAppWhenRun = false

    @Parameter(title: "Why are you keeping it?", requestValueDialog: "Why are you keeping it?")
    var reason: String

    @Parameter(title: "What to keep", description: "A link or text. Leave empty to keep what you copied.")
    var content: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let keeper = Keeper(context: StoreBox.container.mainContext)
        let text = content ?? UIPasteboard.general.string ?? ""
        let draft = Detection.drafts(fromText: text).first
            ?? Detection.Draft(kind: .note, title: String(reason.prefix(90)), text: reason)
        let (_, outcome) = keeper.keep(draft, reason: SpokenReason.clean(reason), reasonSource: .spoken, source: .actionButton,
                                       events: CalendarReader.upcoming())
        await Engine.refresh(keeper)
        return .result(dialog: "Kept. \(outcome.moment.explanation).")
    }
}

/// Moment 7: ask Siri, answered in your own words.
struct FindIntent: AppIntent {
    static let title: LocalizedStringResource = "Find in Shoebox"
    static let description = IntentDescription("Find something you kept, by what you said about it.")

    @Parameter(title: "About", requestValueDialog: "What was it about?")
    var about: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        let keeper = Keeper(context: StoreBox.container.mainContext)
        let found = keeper.search(about)
        guard let first = found.first else { return .result(dialog: "I don't see anything you kept about \(about).") }
        var answer = "You kept \(first.title)"
        if !first.reason.isEmpty { answer += ", \u{201C}\(first.reason)\u{201D}" }
        if first.status == .quiet { answer += ". It's gone quiet; say bring it back to have it come back" }
        else if let m = keeper.nextMoment(for: first), first.status == .planned { answer += ". \(m.explanation)" }
        if found.count > 1 { answer += ". And \(found.count - 1) more." }
        return .result(opensIntent: OpenSaveIntent(id: first.id.uuidString), dialog: IntentDialog(stringLiteral: answer))
    }
}

/// "Bring back the campsite thing" (SPEC 5).
struct BringBackIntent: AppIntent {
    static let title: LocalizedStringResource = "Bring back from Shoebox"
    static let description = IntentDescription("Bring a quiet or let-go save back. Shoebox picks the time.")

    @Parameter(title: "About", requestValueDialog: "Which one?")
    var about: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let keeper = Keeper(context: StoreBox.container.mainContext)
        guard let s = keeper.search(about).first else { return .result(dialog: "I don't see anything about \(about).") }
        keeper.bringBack(s, .youChoose, events: CalendarReader.upcoming())
        await Engine.refresh(keeper)
        let when = keeper.nextMoment(for: s)?.explanation ?? "It's coming back"
        return .result(dialog: "\(s.headline). \(when).")
    }
}

struct OpenSaveIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a save"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Save") var id: String

    init() {}
    init(id: String) { self.id = id }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.showing = UUID(uuidString: id)
        return .result()
    }
}

struct ShoeboxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KeepIntent(), phrases: ["Keep this in \(.applicationName)", "Save this to \(.applicationName)"],
                    shortTitle: "Keep", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: FindIntent(), phrases: ["Find in \(.applicationName)", "What did I keep in \(.applicationName)"],
                    shortTitle: "Find", systemImageName: "magnifyingglass")
        AppShortcut(intent: BringBackIntent(), phrases: ["Bring back from \(.applicationName)"],
                    shortTitle: "Bring back", systemImageName: "arrow.uturn.backward")
    }
}

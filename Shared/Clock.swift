import Foundation

/// The app's "now". Always the real time in a release build. In a debug build with `-demo YES`, `-dayOffset N` moves it
/// N days ahead, so the UX audit can replay weeks of a life (a newsletter's dates coming back, past events moving to Kept)
/// in one run. Read once at launch.
enum Clock {
    #if DEBUG
    static let offset: TimeInterval = UserDefaults.standard.bool(forKey: "demo")
        ? UserDefaults.standard.double(forKey: "dayOffset") * 86_400 : 0
    #else
    static let offset: TimeInterval = 0
    #endif

    static var now: Date { Date().addingTimeInterval(offset) }
}

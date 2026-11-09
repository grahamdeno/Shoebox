import Foundation

/// The app's "now". Always the real time in a release build. In a debug build with `-demo YES`:
/// - `-demoDate 2026-11-07` starts the clock at 10 AM that day, so the UX audit's pictures show the same dates on every
///   run and can be compared run to run;
/// - `-dayOffset N` moves it N days on from there (or from today), so the audit can replay weeks of a life (a
///   newsletter's dates coming back, past events moving to Kept) in one run.
/// Read once at launch.
enum Clock {
    #if DEBUG
    static let offset: TimeInterval = {
        let d = UserDefaults.standard
        guard d.bool(forKey: "demo") else { return 0 }
        var base: TimeInterval = 0
        if let s = d.string(forKey: "demoDate"), !s.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            if let start = f.date(from: s + " 10:00") { base = start.timeIntervalSince(Date()) }
        }
        return base + d.double(forKey: "dayOffset") * 86_400
    }()
    #else
    static let offset: TimeInterval = 0
    #endif

    static var now: Date { Date().addingTimeInterval(offset) }
}

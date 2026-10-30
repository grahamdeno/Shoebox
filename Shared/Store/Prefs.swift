import Foundation
import ShoeboxCore

/// Settings (SPEC 1.6), kept in the App Group's defaults so every part of Shoebox reads the same values.
/// [Check] The spec has one Settings record in the store; defaults are simpler to share with extensions
/// and are exported in the backup the same way.
struct Prefs: Codable, Equatable, Sendable {
    var palette: String = "plum"                 // "plum" or "gold"
    var weekdayIssue = DayTimeValue(hour: 7, minute: 0)
    var weekendIssue = DayTimeValue(hour: 8, minute: 0)
    var homeEveningStart = DayTimeValue(hour: 18, minute: 0)
    var homeEveningEnd = DayTimeValue(hour: 20, minute: 30)
    var workStart = DayTimeValue(hour: 9, minute: 0)
    var workEnd = DayTimeValue(hour: 17, minute: 0)
    var dailyBudget = 4
    var statsOff = false
    var onboarded = false
    var importChecked = false
    var inboxKey: String?
    var inboxAddress: String?
    var aiConsent: String?
    var aiDevice: String?
    var aiToken: String?
    var aiAttested: String?
    var schoolOn = false
    var schoolChild = ""
    var schoolName = ""
    var schoolAbout = ""
    var schoolWords: [String] = []
    var schoolDays: [Int] = [1, 5]
    var homeAnswers: [Int] = []                  // minutes after midnight of answered home-evening moments

    private static let key = "shoebox.prefs"

    static func load() -> Prefs {
        guard let d = AppGroup.defaults.data(forKey: key), let p = try? JSONDecoder().decode(Prefs.self, from: d) else { return Prefs() }
        return p
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { AppGroup.defaults.set(d, forKey: Self.key) }
    }

    static func update(_ change: (inout Prefs) -> Void) {
        var p = load(); change(&p); p.save()
    }

    var plannerSettings: PlannerSettings {
        var s = PlannerSettings.standard
        s.weekdayIssue = weekdayIssue.dayTime
        s.weekendIssue = weekendIssue.dayTime
        s.homeEveningStart = homeEveningStart.dayTime
        s.homeEveningEnd = homeEveningEnd.dayTime
        s.workStart = workStart.dayTime
        s.workEnd = workEnd.dayTime
        return s
    }
}

struct DayTimeValue: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int
    var dayTime: DayTime { DayTime(hour, minute) }

    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var label: String {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        let d = Calendar.current.date(from: c) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
}

import Foundation

/// Rule 3: ignored twice, it goes quiet (SPEC 5).
public enum QuietRule {
    public static let passesToQuiet = 2
    /// School info posts are news: one pass and they go quiet (SPEC 7.5).
    public static let schoolInfoPassesToQuiet = 1
    public static let notificationWindow: TimeInterval = 3 * 3600
    /// Quiet hours start at 9:00 PM (SPEC 4.2).
    public static let quietHoursStartHour = 21
    /// The Later that asks "Keep it, or let it go quiet?" instead of planning (SPEC 3).
    public static let latersBeforeQuestion = 3

    public enum PassResult: Sendable, Equatable { case replan, quiet }

    /// When a delivered moment's window closes with no verdict (and so counts as a pass).
    /// - notification: 3 hours after delivery or 9:00 PM that day, whichever is sooner.
    /// - issue: 11:59 PM on the day it was delivered.
    /// - liveActivity: when the anchor event starts.
    public static func windowEnd(surface: MomentSurface, deliveredAt: Date, anchorStart: Date?, calendar: Calendar) -> Date {
        let threeHours = deliveredAt.addingTimeInterval(notificationWindow)
        switch surface {
        case .notification:
            // [Check] A moment you set yourself inside quiet hours (R1) is delivered after 9 PM;
            // its window is then the plain 3 hours rather than closing before it opened.
            guard let nine = calendar.date(bySettingHour: quietHoursStartHour, minute: 0, second: 0, of: deliveredAt),
                  nine > deliveredAt else { return threeHours }
            return min(threeHours, nine)
        case .issue:
            if let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: deliveredAt) { return end }
            return calendar.startOfDay(for: deliveredAt).addingTimeInterval(23 * 3600 + 59 * 60)
        case .liveActivity:
            // [Check] Without a known anchor start, fall back to the notification window.
            guard let anchorStart else { return threeHours }
            return max(anchorStart, deliveredAt)
        }
    }

    /// What happens after a pass. `passes` is the new count, this pass included.
    public static func afterPass(passes: Int) -> PassResult {
        passes >= passesToQuiet ? .quiet : .replan
    }

    /// Same, with school info posts going quiet after one pass.
    public static func afterPass(passes: Int, isSchoolInfo: Bool) -> PassResult {
        passes >= (isSchoolInfo ? schoolInfoPassesToQuiet : passesToQuiet) ? .quiet : .replan
    }

    /// Whether this Later should ask "Keep it, or let it go quiet?" instead of planning.
    /// `laters` is the new count, this Later included (same convention as `afterPass`), so 3 asks.
    public static func laterNeedsQuestion(laters: Int) -> Bool { laters >= latersBeforeQuestion }
}

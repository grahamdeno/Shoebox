import Foundation

/// Tidying a spoken reason (SPEC 2.3, "Spoken reasons"): filler at the start removed,
/// first letter capitalized, cut at 140 characters on a word boundary.
public enum SpokenReason {
    public static let maxLength = 140

    /// "um", "uh", "uhm", "erm", "hmm" as whole words, and "like," with its comma, repeated at the start.
    /// [Check] "like" without a comma stays, so "Like this one" keeps its meaning.
    static let fillerPattern = "^(?:(?:u+h*m+|u+h+|e+r+m+|h+m+)\\b[\\s,.\u{2026}]*|like,\\s*)+"

    public static func clean(_ s: String) -> String {
        var out = RulesRegex.trim(s)
        out = RulesRegex.replace(fillerPattern, in: out, with: "", options: [.caseInsensitive])
        out = RulesRegex.capitalizeFirst(RulesRegex.trim(out))
        return clip(out, max: maxLength)
    }

    /// Cut to `max` characters, at the last word boundary that fits. A single word longer than
    /// `max` is cut hard. No ellipsis is added. Trailing spaces and commas are dropped.
    public static func clip(_ s: String, max: Int = 140) -> String {
        let t = RulesRegex.trim(s)
        if max <= 0 { return "" }
        if t.count <= max { return t }
        let head = String(t.prefix(max))
        let next = t.index(t.startIndex, offsetBy: max)
        if t[next].isWhitespace { return trimTail(head) }
        if let space = head.lastIndex(where: { $0.isWhitespace }), space > head.startIndex {
            return trimTail(String(head[..<space]))
        }
        return head
    }

    static func trimTail(_ s: String) -> String { RulesRegex.replace("[\\s,;:]+$", in: s, with: "") }
}

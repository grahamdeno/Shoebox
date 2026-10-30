import Foundation

/// The child's name stays on the phone (SPEC 7.3). Ported from the old app.js `childNames` and
/// ai.js `CHILD_TOKEN`, `maskNames`, `nameIn`.
public enum NameMask {
    /// What the AI sees and writes in place of the child's name, braces included.
    public static let token = "{child}"
    /// What the token becomes when no name is set.
    public static let standIn = "your child"

    /// The names in the `child` setting, split on commas or the word "and" (old `childNames`).
    public static func names(from child: String) -> [String] {
        RulesRegex.split(",|\\band\\b", child).map { RulesRegex.trim($0) }.filter { !$0.isEmpty }
    }

    /// Each name of 2+ characters, as a whole word in any case, becomes `{child}` (old `maskNames`).
    public static func mask(_ text: String, child: String) -> String {
        var out = text
        let template = NSRegularExpression.escapedTemplate(for: token)
        for name in names(from: child) where name.count > 1 {
            out = RulesRegex.replace(wholeWord(name), in: out, with: template, options: [.caseInsensitive])
        }
        return out
    }

    /// `{child}` (any case) back to the first name, or "your child" when none is set (old `nameIn`).
    /// [Check] 2.0 capitalizes "Your child" at the start of any sentence, not only at the start of the text.
    public static func unmask(_ text: String, child: String) -> String {
        let first = names(from: child).first ?? ""
        let put = first.isEmpty ? standIn : first
        var out = RulesRegex.replace("\\{child\\}", in: text, with: NSRegularExpression.escapedTemplate(for: put),
                                     options: [.caseInsensitive])
        out = RulesRegex.replace("(^|[.!?]\\s+|\\n\\s*)your child", in: out, with: "$1Your child")
        return out
    }

    /// Whether the text names the child (any name of 2+ characters, whole word, any case) or holds the token.
    public static func mentions(_ text: String, child: String) -> Bool {
        if text.range(of: token, options: .caseInsensitive) != nil { return true }
        for name in names(from: child) where name.count > 1 {
            if RulesRegex.test(wholeWord(name), text, options: [.caseInsensitive]) { return true }
        }
        return false
    }

    static func wholeWord(_ name: String) -> String { "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b" }
}

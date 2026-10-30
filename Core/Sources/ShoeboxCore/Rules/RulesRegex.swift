import Foundation

/// Small NSRegularExpression helpers shared by the rules in this folder.
/// Patterns are compiled per call: the inputs are short, and it keeps every rule free of
/// shared mutable or non-Sendable state under Swift 6 strict concurrency.
enum RulesRegex {
    static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    static func whole(_ s: String) -> NSRange { NSRange(s.startIndex..<s.endIndex, in: s) }

    static func first(_ pattern: String, in s: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let re = make(pattern, options) else { return nil }
        return re.firstMatch(in: s, options: [], range: whole(s))
    }

    static func all(_ pattern: String, in s: String, options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let re = make(pattern, options) else { return [] }
        return re.matches(in: s, options: [], range: whole(s))
    }

    static func test(_ pattern: String, _ s: String, options: NSRegularExpression.Options = []) -> Bool {
        first(pattern, in: s, options: options) != nil
    }

    /// The text of capture group `i`, or nil when the group took no part in the match.
    static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }

    /// Every whole match, in order.
    static func strings(_ pattern: String, in s: String, options: NSRegularExpression.Options = []) -> [String] {
        all(pattern, in: s, options: options).compactMap { group($0, 0, in: s) }
    }

    static func replace(_ pattern: String, in s: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = make(pattern, options) else { return s }
        return re.stringByReplacingMatches(in: s, options: [], range: whole(s), withTemplate: template)
    }

    /// Split on every match of the pattern, like JavaScript's `split(/re/)`.
    static func split(_ pattern: String, _ s: String, options: NSRegularExpression.Options = []) -> [String] {
        let ns = s as NSString
        var parts: [String] = []
        var loc = 0
        for m in all(pattern, in: s, options: options) {
            parts.append(ns.substring(with: NSRange(location: loc, length: m.range.location - loc)))
            loc = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: loc))
        return parts
    }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func hasNewline(_ s: String) -> Bool { s.unicodeScalars.contains { $0 == "\n" } }

    static func wordCount(_ s: String) -> Int { s.split(whereSeparator: { $0.isWhitespace }).count }

    static func capitalizeFirst(_ s: String) -> String { String(s.prefix(1)).uppercased() + String(s.dropFirst()) }
}

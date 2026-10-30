import Foundation

/// The three answers every moment carries (SPEC 3).
public enum Verdict: String, Sendable, CaseIterable { case done, later, drop }

/// What a school post asks of the parent (SPEC 7.4).
public enum SchoolPostKind: String, Sendable, Codable { case action, decision, info }

/// Button words for the verdicts (SPEC 3).
public enum VerdictWords {
    /// The Done button's word. School posts and books first ([Old]), then the intent, then the kind.
    public static func doneWord(kind: SaveKind, intent: Intent?, reason: String, isBook: Bool, school: SchoolPostKind?) -> String {
        if let school {
            switch school {
            case .action: return "Done"
            case .decision: return "Decided"
            case .info: return "Got it"
            }
        }
        if isBook { return "I've read it" }
        switch intent {
        case .read?: return "Read"
        case .watch?: return "Watched"
        case .listen?: return "Listened"
        case .idea?: return "Tried it"
        case .reference?: return "Kept"
        case .task?: return reasonVerb(reason) ?? "Done"
        case nil: break
        }
        // [Check] No intent yet (AI hasn't run): a reason that starts with a doing word still wins,
        // then the kind decides. Notes and files read as tasks.
        if let verb = reasonVerb(reason) { return verb }
        switch kind {
        case .link, .pdf: return "Read"
        case .video: return "Watched"
        case .photo, .quote: return "Kept"
        case .note, .file: return "Done"
        }
    }

    /// "Not for me" on anything Shoebox suggested, otherwise "Drop".
    public static func dropWord(suggested: Bool) -> String { suggested ? "Not for me" : "Drop" }

    /// Past tense of the reason's first word when it is a doing word ("Book the campsite" gives "Booked").
    /// [Check] The list goes beyond the spec's four examples (Booked, Ordered, Signed, Called).
    static let pastTense: [String: String] = [
        "book": "Booked", "order": "Ordered", "sign": "Signed", "call": "Called", "buy": "Bought",
        "pay": "Paid", "email": "Emailed", "text": "Texted", "register": "Registered", "schedule": "Scheduled",
        "reply": "Replied", "send": "Sent", "submit": "Submitted", "renew": "Renewed", "cancel": "Cancelled",
        "return": "Returned", "reserve": "Reserved", "apply": "Applied", "donate": "Donated", "rsvp": "RSVP'd",
    ]

    static func reasonVerb(_ reason: String) -> String? {
        guard let first = RulesRegex.trim(reason).split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let word = String(first).lowercased().trimmingCharacters(in: .punctuationCharacters)
        return pastTense[word]
    }
}

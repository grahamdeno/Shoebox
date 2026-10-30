import Foundation

/// Time to read or watch when AI hasn't said (SPEC 2.4). Old model.js `estimateMinutes`, plus
/// `BOOK_SITTING_MINUTES` for books.
public enum Minutes {
    /// What a book costs: one sitting.
    public static let bookSitting = 30
    public static let wordsPerMinute = 220

    public static func estimate(kind: SaveKind, text: String?, isBook: Bool) -> Int {
        if isBook { return bookSitting }
        switch kind {
        case .note:
            let words = RulesRegex.wordCount(text ?? "")
            return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
        case .quote, .photo: return 1
        case .link: return 6
        case .pdf: return 15
        case .video: return 10
        case .file: return 5
        }
    }
}

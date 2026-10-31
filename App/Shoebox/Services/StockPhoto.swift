import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Finds a stock picture for a post that has none.
///
/// The thinking happens on the phone. Apple Intelligence turns the post into two to four generic words
/// ("school gym string lights") and later picks the best of the candidates by their captions. Only those
/// words go to Shoebox's server, never names, your text or your reason. Without Apple Intelligence a short
/// list of plain keyword rules does the first step, and the first candidate is the pick.
/// Posts about health, money or legal matters are never looked up.
@MainActor
enum StockPhoto {
    struct Candidate: Decodable {
        var id: String
        var url: String
        var alt: String?
        var by: String?
        var page: String?
    }
    private struct Reply: Decodable { var photos: [Candidate] }

    /// Finds, picks and keeps a picture. A miss is retried tomorrow, not on every launch.
    /// A lookup cut short (you swiped on) is not counted as a try, and a picture is only kept if the post
    /// is still there and still has none.
    static func fill(_ s: Save) async {
        guard Prefs.stockPictures, s.imageData == nil, s.deletedAt == nil, s.kind != .photo else { return }
        if let tried = s.stockTriedAt, Date().timeIntervalSince(tried) < 86_400 { return }
        let previous = s.stockTriedAt
        s.stockTriedAt = Date()
        func gone() -> Bool { s.modelContext == nil || s.isDeleted || s.deletedAt != nil }
        func release() { if !gone() { s.stockTriedAt = previous } }

        let words = await phrase(for: s)
        if Task.isCancelled { release(); return }
        guard let phrase = words else { return }
        let found = await search(phrase)
        if Task.isCancelled { release(); return }
        guard let candidates = found, !candidates.isEmpty else { return }
        let choice = await pick(from: candidates, phrase: phrase)
        guard let url = URL(string: choice.url) else { return }
        let data = await Relay.picture(url)
        if Task.isCancelled { release(); return }
        guard let data, !gone(), s.imageData == nil else { return }
        s.imageData = data
        s.imageURL = choice.url
        s.imageSource = "stock"
        s.imageCredit = choice.by.map { "Photo by \($0) on Pixabay" } ?? "Photo from Pixabay"
        s.imageCreditURL = choice.page
        s.updatedAt = Date()
    }

    // MARK: The words

    /// Two to four generic words for the post, or nil when it shouldn't be looked up.
    /// Everything you wrote is checked for health, money and legal words; only title, description and the start
    /// of the text are used to make the words, and only words from a fixed list of plain scene words are ever sent.
    static func phrase(for s: Save) async -> String? {
        let everything = [s.title, s.snippet, s.note, String(s.body.prefix(20_000))].filter { !$0.isEmpty }.joined(separator: ". ")
        let source = [s.title, s.snippet, String(s.body.prefix(400))].filter { !$0.isEmpty }.joined(separator: ". ")
        guard !source.isEmpty, !isSensitive(everything) else { return nil }
        // Plain scene words stay allowed even when capitalized ("the Halloween Dance"); names are not on the list anyway.
        let banned = properNouns(in: everything).subtracting(vocabulary)
        if let p = await OnDeviceAI.photoWords(for: source), let ok = clean(p, banned: banned) { return ok }
        if let p = keywordPhrase(source), let ok = clean(p, banned: banned) { return ok }
        return nil
    }

    /// Lowercase letters and spaces, one to five words, each from the list of plain scene words,
    /// and nothing that looks like a name from the post.
    static func clean(_ raw: String, banned: Set<String>) -> String? {
        let letters = raw.lowercased().map { $0.isLetter ? $0 : " " }
        let words = String(letters).split(separator: " ").map(String.init)
        guard (1...5).contains(words.count),
              words.allSatisfy({ $0.count >= 3 && vocabulary.contains($0) && !banned.contains($0) }) else { return nil }
        return words.joined(separator: " ")
    }

    private static let titles: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "mt", "vs", "coach", "fr", "rev"]

    /// Capitalized words that don't start a sentence (names of people, schools, places), also in pieces
    /// ("Emma's" gives emma, "Smith-Jones" gives smith and jones). A title like "Mrs." doesn't end a sentence.
    static func properNouns(in text: String) -> Set<String> {
        var out = Set<String>()
        var startsSentence = true
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            if let first = word.first, first.isUppercase, !startsSentence {
                for piece in word.lowercased().split(whereSeparator: { !$0.isLetter }) where piece.count >= 2 { out.insert(String(piece)) }
            }
            if let last = raw.last, ".!?\n".contains(last) {
                startsSentence = !titles.contains(word.lowercased())
            } else {
                startsSentence = false
            }
        }
        return out
    }

    /// Whole words that mean health, money or legal matters.
    private static let sensitiveWords: Set<String> = [
        "bank", "banks", "loan", "loans", "tax", "court", "ssn", "bill", "bills", "rent", "irs", "pin", "visa",
    ]
    /// Word beginnings that mean the same.
    private static let sensitiveStems = [
        "doctor", "dentist", "dental", "clinic", "hospital", "therap", "counsel", "prescri", "diagnos", "surger",
        "medic", "health", "pregnan", "mortgage", "invoice", "salary", "taxes", "credit", "debt", "lawyer",
        "attorney", "divorce", "lawsuit", "custody", "password", "insur", "pharmac", "bankrupt", "police",
        "cancer", "payroll", "paycheck", "legal", "subpoena", "arrest",
    ]
    private static let courtSports: Set<String> = ["basketball", "tennis", "volleyball", "pickleball", "squash", "badminton", "food"]

    static func isSensitive(_ text: String) -> Bool {
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for (i, w) in tokens.enumerated() {
            if w == "court", i > 0, courtSports.contains(tokens[i - 1]) { continue }
            if sensitiveWords.contains(w) || sensitiveStems.contains(where: { w.hasPrefix($0) }) { return true }
        }
        return false
    }

    /// The only words that ever leave the phone: plain things you could photograph.
    private static let vocabulary: Set<String> = Set("""
        halloween pumpkins pumpkin autumn fall leaves orchard harvest costume party string lights celebration confetti \
        balloons dance gym school classroom books library desk pencils notebook students playground soccer lacrosse \
        football basketball baseball softball field court stadium running trail trails runner marathon swimming pool \
        swim concert stage music guitar piano trumpet band orchestra microphone mountain mountains hiking camping tent \
        forest lake river ocean beach sunset sunrise sand waves coast island airport window airplane travel landscape \
        road city street skyline bridge train hotel suitcase map kitchen cooking baking bread coffee cup tea breakfast \
        dinner table dessert cake cookies fruit vegetables salad pizza reading book laptop computer coding code keyboard \
        office meeting room whiteboard workshop team garden flowers plants tree trees spring summer winter snow rain \
        clouds sky morning evening night moon stars holiday christmas gifts candles fireplace cozy home house living \
        bicycle bike skateboard yoga fitness weights walking park dog cat birds horse farm barn tractor fishing boat \
        sailing painting art studio paper craft camera photography notebook journal calendar clock desk lamp window \
        community market festival fair parade fireworks picnic grill barbecue snack sports team trophy medal ribbon \
        science lab telescope robot circuit machine tools workshop wood carpentry
        """.split(whereSeparator: { $0.isWhitespace || $0 == "\\" }).map(String.init))

    /// Plain keyword rules for phones without Apple Intelligence.
    static func keywordPhrase(_ text: String) -> String? {
        let t = " " + text.lowercased() + " "
        let rules: [([String], String)] = [
            (["halloween", "pumpkin", "costume"], "halloween pumpkins"),
            (["dance", "prom", "party", "celebration"], "party string lights"),
            (["soccer"], "soccer field"), (["lacrosse"], "lacrosse field"), (["football"], "football field"),
            (["basketball"], "basketball court"), (["baseball", "softball"], "baseball field"),
            (["cross country", "marathon", " 5k", "running", " run "], "trail running"),
            (["swim"], "swimming pool"),
            (["band", "concert", "music", "trumpet", "orchestra", "recital"], "concert stage lights"),
            (["hike", "hiking", "trail", "camping", "campsite"], "mountain trail"),
            (["beach"], "beach sunset"), (["flight", "airport"], "airport window"),
            (["trip", "travel", "vacation", "hotel", "itinerary"], "travel landscape"),
            (["recipe", "dinner", "cook", "bake", "baking"], "kitchen cooking"), (["coffee"], "coffee cup"),
            (["school", "classroom", "teacher", "pta", "homework"], "school classroom"),
            (["book", "novel", "reading"], "reading book"),
            (["software", "code", "coding", "app "], "laptop desk"),
            (["meeting", "agenda", "workshop"], "meeting room"),
            (["garden", "plants", "flowers"], "garden flowers"),
        ]
        for (keys, phrase) in rules where keys.contains(where: { t.contains($0) }) { return phrase }
        return nil
    }

    // MARK: The server and the pick

    private static func search(_ phrase: String) async -> [Candidate]? {
        let req = Relay.request("stock", query: [.init(name: "q", value: phrase), .init(name: "n", value: "6")])
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.photos
    }

    private static func pick(from candidates: [Candidate], phrase: String) async -> Candidate {
        guard candidates.count > 1 else { return candidates[0] }
        if let i = await OnDeviceAI.bestPhoto(phrase: phrase, captions: candidates.map { $0.alt ?? "" }),
           candidates.indices.contains(i) { return candidates[i] }
        // No Apple Intelligence: the caption that shares the most words with the search, else the server's first.
        let want = Set(phrase.split(separator: " ").map(String.init))
        let scored = candidates.enumerated().map { (i, c) -> (Int, Int) in
            let words = Set((c.alt ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            return (i, words.intersection(want).count)
        }
        let best = scored.max { a, b in a.1 == b.1 ? a.0 > b.0 : a.1 < b.1 }
        return candidates[best?.0 ?? 0]
    }
}

/// Apple Intelligence on the phone, when there is one. Nothing here leaves the device.
enum OnDeviceAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Two to four generic words for a stock photo search.
    static func photoWords(for text: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You write stock photo search words. Reply with two to four plain lowercase words describing a concrete, \
            friendly, generic scene that suits the text. Never include names of people, schools, companies or places, \
            and never dates. Avoid anything medical, financial or legal.
            """)
        let r = try? await session.respond(to: "Text: \(String(text.prefix(600)))", generating: PhotoIdea.self)
        return r?.content.words
        #else
        return nil
        #endif
    }

    /// The index of the caption that best fits the search words.
    static func bestPhoto(phrase: String, captions: [String]) async -> Int? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let list = captions.enumerated().map { "\($0.offset): \($0.element.isEmpty ? "(no caption)" : $0.element)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: "You choose the stock photo caption that best matches the search words. Answer with its number.")
        let r = try? await session.respond(to: "Search: \(phrase)\nCaptions:\n\(list)", generating: PhotoChoice.self)
        return r?.content.number
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct PhotoIdea {
    @Guide(description: "Two to four plain lowercase words for a stock photo search. No names, no dates.")
    var words: String
}

@Generable
struct PhotoChoice {
    @Guide(description: "The number of the best matching caption.")
    var number: Int
}
#endif

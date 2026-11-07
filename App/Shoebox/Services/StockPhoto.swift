import Foundation
import SwiftData
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

    /// Where a look for a picture stopped. Counted on the phone only (Settings › Pictures), never sent anywhere.
    enum Outcome: String, CaseIterable {
        case found, notLookedUp, noPlainWords, notItsSubject, serverBusy, serverNo, noneFound, downloadFailed, skipped
    }

    /// Counts for the last pass over the Shoebox, shown as one quiet line in Settings › Pictures.
    static func record(_ o: Outcome) {
        guard o != .skipped else { return }
        var log = Prefs.pictureLog
        log[o.rawValue, default: 0] += 1
        Prefs.pictureLog = log
    }

    /// Finds, picks and keeps a picture. A miss is retried tomorrow, not on every launch.
    /// A lookup cut short (you swiped on) is not counted as a try, and a picture is only kept if the post
    /// is still there and still has none.
    @discardableResult
    static func fill(_ s: Save) async -> Outcome {
        guard Prefs.stockPictures, s.imageData == nil, s.deletedAt == nil, s.kind != .photo else { return .skipped }
        if recentlyTried(s) { return .skipped }
        let previous = s.stockTriedAt
        s.stockTriedAt = Clock.now
        func gone() -> Bool { s.modelContext == nil || s.isDeleted || s.deletedAt != nil }
        func release() { if !gone() { s.stockTriedAt = previous } }

        if isSensitive(sensitivityText(s)) { return .notLookedUp }
        // The title's own plain words ("delivery", "tickets", "soccer field"), never a name from the post.
        let titleWords = clean(s.title, banned: properNouns(in: s.title).subtracting(vocabulary))
        let words = await phrase(for: s)
        if Task.isCancelled { release(); return .skipped }
        // A dated post from email (a newsletter date) gets a picture of its own subject or none: the search must
        // name something in its title ("trumpet", "lacrosse"), not a stand-in like a mountain or a classroom.
        // When the suggested words miss the title, the title's own plain words are searched instead.
        let datedEmail = s.kind == .email && s.eventDate != nil
        let chosen: String?
        if datedEmail {
            chosen = words.flatMap { sharesWord($0, with: s.title) ? $0 : nil } ?? titleWords
        } else {
            chosen = words ?? titleWords
        }
        guard let phrase = chosen else { return words == nil && titleWords == nil ? .noPlainWords : .notItsSubject }
        let (found, status) = await search(phrase)
        if Task.isCancelled { release(); return .skipped }
        guard let found else {
            // A busy server (429) or no answer is not the post's fault: try it again on the next opening.
            release()
            if status != 429 { var log = Prefs.pictureLog; log["code"] = status; Prefs.pictureLog = log }
            return status == 429 ? .serverBusy : .serverNo
        }
        // Never the same picture twice: one already on another post is skipped.
        let used = Set(((try? s.modelContext?.fetch(FetchDescriptor<Save>())) ?? [])
            .filter { $0.id != s.id && $0.imageSource == "stock" }.compactMap(\.imageURL))
        let candidates = found.filter { !used.contains($0.url) }
        guard !candidates.isEmpty else { return .noneFound }
        let choice = await pick(from: candidates, phrase: phrase)
        guard let url = URL(string: choice.url) else { return .noneFound }
        let data = await Relay.picture(url)
        if Task.isCancelled { release(); return .skipped }
        guard let data else { release(); return .downloadFailed }
        guard !gone(), s.imageData == nil else { return .skipped }
        s.imageData = data
        s.imageURL = choice.url
        s.imageSource = "stock"
        s.imageCredit = choice.by.map { "Photo by \($0) on Pixabay" } ?? "Photo from Pixabay"
        s.imageCreditURL = choice.page
        s.updatedAt = Clock.now
        return .found
    }

    /// What is read for health, money and legal words: your title, the description, your reason and the start of the
    /// text. Not the whole email: almost every email ends in a footer with "Legal", "credit" or "insurance" in it,
    /// which kept nearly every emailed post from ever getting a picture.
    static func sensitivityText(_ s: Save) -> String {
        [s.title, s.snippet, s.note, String(s.body.prefix(1_500))].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// Tried within the last day.
    static func recentlyTried(_ s: Save, now: Date = Clock.now) -> Bool {
        guard let tried = s.stockTriedAt else { return false }
        return now.timeIntervalSince(tried) < 86_400
    }

    /// Once, after the word rules were widened (November 4, 2026): every post still without a picture gets a fresh try,
    /// whenever it was last tried under the old rules.
    static func forgetOldTries(_ saves: [Save]) -> Int {
        guard !Prefs.stockRulesWidened3 else { return 0 }
        var n = 0
        for s in saves where s.imageData == nil && s.stockTriedAt != nil { s.stockTriedAt = nil; n += 1 }
        Prefs.stockRulesWidened3 = true
        return n
    }

    /// True when a word of the phrase (or its singular) is in the title.
    static func sharesWord(_ phrase: String, with title: String) -> Bool {
        let t = Set(title.lowercased().split(whereSeparator: { !$0.isLetter }).map { String($0) })
        let tSingular = Set(t.map { $0.hasSuffix("s") ? String($0.dropLast()) : $0 })
        return phrase.split(separator: " ").contains { w in
            let word = String(w)
            let singular = word.hasSuffix("s") ? String(word.dropLast()) : word
            return word.count >= 4 && (t.contains(word) || tSingular.contains(singular))
        }
    }

    // MARK: The words

    /// Two to four generic words for the post, or nil when it shouldn't be looked up.
    /// Everything you wrote is checked for health, money and legal words; only title, description and the start
    /// of the text are used to make the words, and only words from a fixed list of plain scene words are ever sent.
    static func phrase(for s: Save) async -> String? {
        let everything = sensitivityText(s)
        let source = [s.title, s.snippet, String(s.body.prefix(400))].filter { !$0.isEmpty }.joined(separator: ". ")
        guard !source.isEmpty, !isSensitive(everything) else { return nil }
        // Plain scene words stay allowed even when capitalized ("the Halloween Dance"); names are not on the list anyway.
        let banned = properNouns(in: everything).subtracting(vocabulary)
        if let p = await OnDeviceAI.photoWords(for: source), let ok = clean(p, banned: banned) { return ok }
        if let p = keywordPhrase(source), let ok = clean(p, banned: banned) { return ok }
        return nil
    }

    /// Only the words from the list of plain scene words are kept, never one that looks like a name from the post, and at
    /// most four. Words off the list are dropped, not the whole phrase: "laundry room washing machine" still finds a
    /// laundry room. Nil when no listed word is left.
    static func clean(_ raw: String, banned: Set<String>) -> String? {
        let letters = raw.lowercased().map { $0.isLetter ? $0 : " " }
        var seen = Set<String>()
        let words = String(letters).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && vocabulary.contains($0) && !banned.contains($0) && seen.insert($0).inserted }
        guard !words.isEmpty else { return nil }
        return words.prefix(4).joined(separator: " ")
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
        science lab telescope robot circuit machine tools workshop wood carpentry washer dryer \
        laundry washing appliance appliances delivery truck package packages boxes moving shopping store cart clothes \
        shoes sneakers jacket fashion jewelry watch watches gift wrapping birthday cupcakes cupcake candy chocolate \
        flowers bouquet wedding family friends kids children toys games puzzle movie cinema theater theatre tickets \
        popcorn museum gallery zoo aquarium amusement carnival rides ferris wheel ice skating rink hockey golf tennis \
        volleyball gymnastics cheer cheerleading track bus car road trip highway gas station parking garage driveway \
        yard lawn porch patio deck pool backyard furniture sofa couch bedroom bed pillow blanket bathroom shower \
        cleaning paint renovation hammer drill ladder plumbing light lights lamp electric solar energy battery phone \
        tablet screen headphones podcast radio news newspaper magazine letter mail envelope stamp postcard pen \
        signature form clipboard checklist notes planner schedule sticky graduation diploma cap gown uniform \
        volunteer charity candle pets puppy kitten aquarium fish garden vegetable \
        apples pumpkin squash soup pasta tacos sushi burger sandwich lunch lunchbox picnic restaurant cafe bakery \
        wine beer cocktail drinks juice smoothie water bottle thanksgiving turkey easter eggs valentine hearts \
        fourth july flag veterans memorial monument history castle
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

    /// Pixabay refuses searches that come too close together (tested November 4: one second apart, most are refused;
    /// six seconds apart, nearly all go through). Searches from this phone wait their turn.
    static let searchGap: TimeInterval = 6
    private static var lastSearch = Date.distantPast

    /// The server's photos for the words, and its status (0 when there was no answer at all; 429 when Pixabay was busy).
    private static func search(_ phrase: String) async -> ([Candidate]?, Int) {
        let wait = searchGap - Clock.now.timeIntervalSince(lastSearch)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        lastSearch = Clock.now
        if Task.isCancelled { return (nil, 0) }
        let req = Relay.request("stock", query: [.init(name: "q", value: phrase), .init(name: "n", value: "6")])
        guard let (data, res) = try? await URLSession.shared.data(for: req) else { return (nil, 0) }
        let http = res as? HTTPURLResponse
        var code = http?.statusCode ?? 0
        // The relay reports Pixabay's own refusal as a 502 with x-reason pixabay-429: that is busy, not broken.
        if code == 502, http?.value(forHTTPHeaderField: "x-reason") == "pixabay-429" { code = 429 }
        guard code == 200 else { return (nil, code) }
        return ((try? JSONDecoder().decode(Reply.self, from: data))?.photos, code)
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

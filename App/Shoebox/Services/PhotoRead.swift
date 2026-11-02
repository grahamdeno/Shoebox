import Foundation
import ShoeboxCore
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a photo on the phone and suggests what to keep: the words, and why. Vision reads the text in the
/// picture, Apple Intelligence tidies it into a title and the details that matter, and the date reader finds
/// the date from those words. Nothing leaves the phone. Suggestions are only ever shown; you decide.
enum PhotoRead {
    struct Gist: Equatable {
        var words: String
        var why: String
    }

    /// The text in a picture, top to bottom. Empty when there is none.
    static func recognizedText(in data: Data) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            guard let image = UIImage(data: data), let cg = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
            guard (try? handler.perform([request])) != nil else { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return String(lines.joined(separator: "\n").prefix(4_000))
        }.value
    }

    /// The suggestion for what was read, or nil when there is nothing worth keeping words for.
    static func gist(from text: String, now: Date = Date()) async -> Gist? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.filter({ $0.isLetter || $0.isNumber }).count >= 8 else { return nil }
        let fallback = plain(clean)
        #if canImport(FoundationModels)
        guard OnDeviceAI.isAvailable else { return fallback }
        let session = LanguageModelSession(instructions: """
            You read the text found in a photo and turn it into a note the person can keep. \
            Give a short title, then the details that matter: what, when, where, a deadline, a price, a code. \
            Use only words and numbers that are in the text; never add a day, time, place or detail it does not state. \
            For why, say in at most six words what the person likely needs to do, or leave it empty if the text asks nothing.
            """)
        guard let r = try? await session.respond(to: String(clean.prefix(2_500)), generating: PhotoNote.self,
                                                 options: GenerationOptions(sampling: .greedy))
        else { return fallback }
        let year = Calendar.current.component(.year, from: now)
        let check = clean + " \(year) \(year + 1)"
        let title = r.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = r.content.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = r.content.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = details.isEmpty ? title : title + "\n" + details
        guard !title.isEmpty, !EmailRules.invents(words, source: check) else { return fallback }
        let goodWhy = !why.isEmpty && !EmailRules.invents(why, source: check)
        return Gist(words: String(words.prefix(600)), why: goodWhy ? String(why.prefix(60)) : "")
        #else
        return fallback
        #endif
    }

    /// Without Apple Intelligence: the first line is the title, the next few lines are the details.
    static func plain(_ text: String) -> Gist? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
        guard let first = lines.first else { return nil }
        let title = String(first.prefix(60))
        var details = ""
        for l in lines.dropFirst() {
            details += (details.isEmpty ? "" : " · ") + l
            if details.count >= 220 { break }
        }
        let words = details.isEmpty ? title : title + "\n" + String(details.prefix(240))
        return Gist(words: words, why: "")
    }
}

#if canImport(FoundationModels)
@Generable
struct PhotoNote {
    @Guide(description: "A short title, at most six words, naming the thing to remember.")
    var title: String
    @Guide(description: "One or two short plain sentences with only the details that matter: when, where, what, price, deadline.")
    var details: String
    @Guide(description: "At most six words on what to do about it, or empty.")
    var why: String
}
#endif

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns an email into a post: a short title and two or three sentences with only what matters. Written on
/// the phone with Apple Intelligence; without it, the subject and the first few useful lines. Never the whole email.
enum EmailPost {
    struct Written: Equatable { var title: String; var text: String }

    static func write(subject: String, lines: [String]) async -> Written {
        let fallback = plain(subject: subject, lines: lines)
        #if canImport(FoundationModels)
        guard OnDeviceAI.isAvailable else { return fallback }
        let email = (["Subject: \(subject)"] + lines).joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You turn an email into a short post for the reader's own feed, so they can act on it without opening the email. \
            Keep only what matters to them: what it is, the day, time and place if there is one, and anything they need to do, \
            pay, bring or reply to. Leave out greetings, signatures, ads, unsubscribe and legal text. Never invent details. \
            Write plainly, in the reader's terms, without saying "this email".
            """)
        guard let r = try? await session.respond(to: String(email.prefix(3_500)), generating: EmailGist.self) else { return fallback }
        let title = r.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = r.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        return Written(title: title.isEmpty ? fallback.title : title, text: String(text.prefix(600)))
        #else
        return fallback
        #endif
    }

    /// Without Apple Intelligence: the subject, and the first useful lines up to about three sentences.
    static func plain(subject: String, lines: [String]) -> Written {
        let useful = lines.filter { l in
            let low = l.lowercased()
            return l.count > 2 && !l.hasPrefix(">") && !l.hasPrefix("http")
                && !["unsubscribe", "view in browser", "privacy policy", "all rights reserved", "sent from my"].contains(where: low.contains)
        }
        var text = ""
        for l in useful {
            text += (text.isEmpty ? "" : " ") + l
            if text.count >= 280 { break }
        }
        if text.count > 320 {
            let cut = text.prefix(320)
            if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > 80 {
                text = String(cut[...end])
            } else {
                text = String(cut).trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        let title = subject.isEmpty ? (useful.first.map { String($0.prefix(80)) } ?? "An email") : subject
        return Written(title: title, text: text)
    }
}

#if canImport(FoundationModels)
@Generable
struct EmailGist {
    @Guide(description: "A short title, at most eight words, naming the thing to remember.")
    var title: String
    @Guide(description: "Two or three short plain sentences with only the details that matter: what, when, where, and what to do.")
    var text: String
}
#endif

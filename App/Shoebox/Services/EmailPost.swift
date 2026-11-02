import Foundation
import ShoeboxCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns an email into a post: a short title and two or three sentences with only what matters. Written on
/// the phone with Apple Intelligence; without it, the subject and the first few useful lines. Never the whole email.
enum EmailPost {
    struct Written: Equatable { var title: String; var text: String }

    static func write(subject: String, lines: [String], received: Date = Date()) async -> Written {
        let fallback = plain(subject: subject, lines: lines)
        #if canImport(FoundationModels)
        guard OnDeviceAI.isAvailable else { return fallback }
        let email = (["Subject: \(subject)"] + lines).joined(separator: "\n")
        let source = String(email.prefix(3_500))
        let session = LanguageModelSession(instructions: """
            You turn an email into a short post for the reader's own feed, so they can act on it without opening the email. \
            Start with what it is or what to do. Keep every date, time, place and amount that matters, any confirmation, \
            order or reference code, a deadline to reply or decide, and each leg of a trip. Leave out greetings, signatures, \
            ads, statistics, unsubscribe and legal text, and card or account numbers. Use only words and numbers from the email: \
            never add a day, time, place or detail it does not state. Write plainly, without saying "this email".
            """)
        guard let r = try? await session.respond(to: source, generating: EmailGist.self, options: GenerationOptions(sampling: .greedy))
        else { return fallback }
        let title = EmailRules.cleanSubject(r.content.title.trimmingCharacters(in: .whitespacesAndNewlines))
        let text = r.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A year the email implies is fine; anything else the email does not hold means the post is not used.
        let year = Calendar.current.component(.year, from: received)
        let check = source + " \(year) \(year + 1)"
        let goodTitle = !title.isEmpty && !EmailRules.invents(title, source: check)
        guard !text.isEmpty, !EmailRules.invents(text, source: check) else {
            return Written(title: goodTitle ? title : fallback.title, text: fallback.text)
        }
        return Written(title: goodTitle ? title : fallback.title, text: String(text.prefix(900)))
        #else
        return fallback
        #endif
    }

    /// Without Apple Intelligence: the subject, and the first useful lines up to about three sentences.
    static func plain(subject: String, lines: [String]) -> Written {
        // Quoted replies are often where the point is ("> Total: $4,150"), so they are read without the marks.
        let unquoted = lines.map { l in
            var t = Substring(l)
            while let f = t.first, f == ">" || f == " " { t = t.dropFirst() }
            return String(t)
        }
        let useful = unquoted.filter { l in
            let low = l.lowercased()
            let replyHeader = low.hasPrefix("on ") && low.hasSuffix("wrote:")
            return l.count > 2 && !l.hasPrefix("http") && !replyHeader
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
        let clean = EmailRules.cleanSubject(subject)
        let title = clean.isEmpty ? (useful.first.map { String($0.prefix(80)) } ?? "An email") : clean
        return Written(title: title, text: text)
    }
}

#if canImport(FoundationModels)
@Generable
struct EmailGist {
    @Guide(description: "A short title, at most eight words, naming the thing to remember.")
    var title: String
    @Guide(description: "Two to five short plain sentences with only the details that matter: what, when, where, what to do, and any code or amount.")
    var text: String
}
#endif

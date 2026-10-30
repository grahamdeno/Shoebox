import Foundation
import PDFKit
import Vision
import ShoeboxCore

/// School newsletters by email (SPEC 7). Each piece that matters for your child becomes its own save.
/// The child's name is replaced with {child} before anything leaves the phone; attachments are read on the
/// phone first and sent as masked text (the 2.0 fix in SPEC 7.3).
@MainActor
enum SchoolMail {
    struct File { var name: String; var mime: String; var data: Data }

    static var settingsReady: Bool {
        let p = Prefs.load()
        return p.schoolOn && (!p.schoolName.isEmpty || !p.schoolWords.isEmpty)
    }

    /// SPEC 7.2: the school's name or any marker word (3+ letters) in the sender, subject, or the first 4,000 characters.
    static func isSchoolMail(from: String, fromName: String, subject: String, text: String) -> Bool {
        let p = Prefs.load()
        guard p.schoolOn else { return false }
        let words = ([p.schoolName] + p.schoolWords).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { $0.count > 2 }
        guard !words.isEmpty else { return false }
        let head = "\(from) \(fromName) \(subject)".lowercased()
        let body = String(text.prefix(4000)).lowercased()
        return words.contains { head.contains($0) || body.contains($0) }
    }

    /// Turns one newsletter into saves. Returns how many were made; nil if the AI couldn't be used.
    static func posts(subject: String, text: String, files: [File], email: EmailInfo, keeper: Keeper) async -> Int? {
        guard RelayAI.consented else { return nil }
        let p = Prefs.load()
        let child = p.schoolChild
        var docText = ""
        for f in files.prefix(6) {
            if let t = read(f), !t.isEmpty { docText += "\n\n--- \(f.name) ---\n" + t }
        }
        let masked = NameMask.mask(EmailRules.stripAds("\(subject)\n\n\(text)\(docText)"), child: child)
        let cal = Calendar.current
        let namedDays = EmailRules.days(in: masked, received: email.receivedAt ?? .now, calendar: cal)
        let about = NameMask.mask(p.schoolAbout.isEmpty ? "the family's child" : p.schoolAbout, child: child)
        let named = !NameMask.names(from: child).isEmpty
        let prompt = Self.prompt(text: masked, about: about, school: p.schoolName, named: named, attachments: files.map(\.name))
        guard let reply = try? await RelayAI.ask(system: system, prompt: prompt) else { return nil }
        let out = RelayAI.json(reply)
        let posts = ((out["posts"] as? [[String: Any]]) ?? []).prefix(16)
        let events = CalendarReader.upcoming()
        var made = 0
        for post in posts {
            let headline = NameMask.unmask(String((post["headline"] as? String ?? "").prefix(90)), child: child)
            let body = NameMask.unmask(String((post["body"] as? String ?? "").prefix(340)), child: child)
            guard !headline.isEmpty || !body.isEmpty else { continue }
            let type = SchoolPostKind(rawValue: post["type"] as? String ?? "") ?? .info
            // Every post must trace to a line of the email, and none may read like an ad (SPEC 7.6).
            let quote = post["quote"] as? String ?? ""
            guard EmailRules.quoteFound(quote, in: masked), !EmailRules.looksLikePromotion(headline + " " + body) else { continue }
            let rawDate = post["date"] as? String
            var date = rawDate.flatMap { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? $0 : nil }
            // A date the email doesn't name is not trusted.
            if let d = date.flatMap({ ISO8601DateFormatter.day.date(from: $0) }), !namedDays.contains(cal.startOfDay(for: d)) { date = nil }
            let school: [String: Any] = ["name": (out["school"] as? String) ?? p.schoolName, "kind": type.rawValue, "date": date ?? NSNull(),
                                         "body": body, "sourceFile": (post["source"] as? String) ?? "email"]
            var draft = Detection.Draft(kind: .note, title: String((headline.isEmpty ? body : headline).prefix(140)), text: body)
            draft.url = nil
            let (s, _) = keeper.keep(draft, reason: String(headline.prefix(140)), reasonSource: .email, source: .school, events: events)
            s.schoolJSON = (try? JSONSerialization.data(withJSONObject: school, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) }
            s.tags = ((post["tags"] as? [String]) ?? []).prefix(2).map { $0.lowercased() }
            s.emailFrom = email.from; s.emailFromName = email.fromName; s.emailSubject = email.subject; s.emailReceivedAt = email.receivedAt
            s.inboxAt = keeper.now()
            if let d = date.flatMap({ ISO8601DateFormatter.day.date(from: $0) }) {
                s.dueDate = d
                s.dueKindRaw = type == .info ? "happening" : "todo"
                keeper.plan(s, events: events)
            } else {
                keeper.plan(s, events: events, reasonText: "tomorrow")
            }
            made += 1
        }
        try? keeper.context.save()
        return made
    }

    /// SPEC 7.5 as planner words: an action or decision with a date comes back 2 days before (deadline words);
    /// info with a date on that day; info without a date at the next Issue.
    static func when(type: SchoolPostKind, date: String?) -> String {
        guard let date, let d = ISO8601DateFormatter.day.date(from: date) else { return "tomorrow" }
        let words = d.formatted(.dateTime.month(.abbreviated).day())
        return type == .info ? words : "by \(words)"
    }

    private static func read(_ f: File) -> String? {
        if f.mime == "application/pdf" || f.name.lowercased().hasSuffix(".pdf") {
            return PDFDocument(data: f.data)?.string.map { String($0.prefix(20000)) }
        }
        if f.mime.hasPrefix("image/") {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            try? VNImageRequestHandler(data: f.data).perform([req])
            return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        if f.mime.hasPrefix("text/") { return String(data: f.data, encoding: .utf8) }
        return nil
    }

    static let system = "You file things a person saved into Shoebox, their private app for what they mean to come back to. Write plainly. No hype, no exclamation marks, no emoji. Reply with JSON only."

    /// The old app's prompt (`ai.js` `schoolPosts`), kept word for word except that attachments arrive as text.
    static func prompt(text: String, about: String, school: String, named: Bool, attachments: [String], today: Date = .now) -> String {
        let t = NameMask.token
        var lines: [String] = []
        lines.append("Today is \(today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())). This is a school newsletter\(school.isEmpty ? "" : " from \(school)").")
        if !attachments.isEmpty {
            lines.append("It came by email with \(attachments.count) attachment\(attachments.count == 1 ? "" : "s") (\(attachments.joined(separator: ", "))), whose text is included below after its file name: read all of it as part of the newsletter. Flyers, calendars and forms often hold the dates and to-dos.")
        }
        lines.append("The parent cares about one child: \(about)")
        if named {
            lines.append("That child is written \(t). Whenever a post is about them, refer to them as \(t), exactly like that with the braces (e.g. \"\(t)'s band concert is Thursday at 7\"), never \"your child\" and never a made-up name.")
        }
        lines += [
            "",
            "Go through it piece by piece. Keep each piece that matters for that child: their grade, their activities and teams, and whole-school dates, deadlines, closings and requests that affect them.",
            "Leave out other grades, other sports and clubs, staff news, fundraising pitches and general filler.",
            "Never make a post from an ad, a sponsor, a promotion, a coupon, spirit wear or anything for sale.",
            "Leave out anything whose date has already passed.",
            "If it's a calendar covering many weeks or the whole year: keep each date in the next 8 weeks that affects this child (no school, early release, holidays and breaks, report cards, conferences, testing, events for their grade). After that, keep only the big ones: breaks, holidays and the last day of school.",
            "Do not summarise or merge: each kept piece becomes its own post, with its specifics (what, when, where, what to bring or do, who to contact, links) kept.",
            "",
            "Return JSON: {",
            "\"school\": string (the school's short name, e.g. \"Lincoln Middle\"),",
            "\"posts\": array of up to 16 {",
            "  \"type\": \"action\" | \"decision\" | \"info\" (action: the family has to do something, like sign, pay, bring, register or show up; decision: they have a choice to make, like whether to sign up, attend or buy; info: good to know, nothing to do),",
            "  \"headline\": string (a catchy line a parent would stop scrolling for, max 70 chars; specific, no clickbait, no emoji),",
            "  \"body\": string (1 to 3 short sentences, max 300 chars, written like a lively school social post: the details of this one piece; at most one exclamation mark; no emoji, no hashtags),",
            "  \"date\": \"YYYY-MM-DD\" or null (the day it happens or is due),",
            "  \"tags\": array of 1-2 lowercase topic words,",
            "  \"source\": string (the attachment's file name if this piece came from an attachment, else \"email\"),",
            "  \"quote\": string (the exact sentence or line from the newsletter this post comes from, copied word for word)",
            "} in the newsletter's order",
            "}",
            "If nothing in it matters for this child, return {\"school\": string, \"posts\": []}.",
            "",
            "Newsletter:",
            text.isEmpty ? "(no text: everything is in the attachments)" : String(text.prefix(30000)),
        ]
        return lines.joined(separator: "\n")
    }
}

extension ISO8601DateFormatter {
    /// "2026-11-20" in the phone's own time zone.
    nonisolated(unsafe) static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

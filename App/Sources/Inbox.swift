import Foundation
import ShoeboxCore

/// Your Shoebox email address (SPEC 2.3, 8). Mail waits on the relay up to 30 days until the app collects it.
/// Each email becomes one save; your note above a forward becomes the reason.
/// [Check] School newsletters are kept as one email save for now; turning them into posts needs the AI work in phase 5.
@MainActor
enum Inbox {
    static let relay = URL(string: "https://shoebox-api.tangomike.app")!
    private static var running = false

    struct Mail: Decodable {
        var id: String
        var from: String?
        var fromName: String?
        var subject: String?
        var text: String?
        var at: Double?
        var links: [String]?
        var attachments: [Part]?
        struct Part: Decodable { var n: Int?; var name: String?; var type: String? }
    }
    struct Response: Decodable { var mails: [Mail]?; var address: String? }
    struct FilePart: Decodable { var data: String? }

    @discardableResult
    static func collect(keeper: Keeper) async -> Int {
        guard !running, let key = Prefs.load().inboxKey else { return 0 }
        running = true
        defer { running = false }
        var req = URLRequest(url: relay.appending(path: "inbox"))
        req.setValue(key, forHTTPHeaderField: "x-inbox-key")
        req.timeoutInterval = 15
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return 0 }
        if let a = r.address { Prefs.update { $0.inboxAddress = a } }
        var done: [String] = []
        let events = CalendarReader.upcoming()
        let existing = keeper.allSaves()
        for m in r.mails ?? [] {
            let subject = (m.subject ?? "").replacingOccurrences(of: #"^((re|fwd?|fw):\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
            let received = m.at.map { Date(timeIntervalSince1970: $0 / 1000) }
            // The same message twice: keep one.
            if existing.contains(where: { $0.emailSubject == subject && $0.emailFrom == m.from && abs(($0.emailReceivedAt ?? .distantPast).timeIntervalSince(received ?? .now)) < 2 * 86_400 }) {
                done.append(m.id); continue
            }
            var (reason, body) = split(m.text ?? "")
            // SPEC 7.6: promotional mail makes no post unless you wrote a note above it (USPS Informed Delivery included).
            if EmailRules.kind(from: m.from ?? "", fromName: m.fromName ?? "", subject: subject, text: m.text ?? "", hasOwnNote: !reason.isEmpty) == .promotional {
                done.append(m.id); continue
            }
            body = EmailRules.stripAds(body)
            var mailText = EmailRules.stripAds(m.text ?? "")
            // A short note and a link (a Smore newsletter): read the linked page.
            if body.count < 400, (m.attachments ?? []).isEmpty, let link = m.links?.first(where: { !$0.lowercased().contains("unsubscribe") }),
               let page = await pageText(link) {
                mailText += "\n\n" + page
                body += "\n\n" + page
            }
            var files: [(data: Data, mime: String, name: String?)] = []
            for (i, part) in (m.attachments ?? []).enumerated().prefix(5) {
                if let d = await file(mail: m.id, n: part.n ?? i, key: key) { files.append((d, part.type ?? "application/octet-stream", part.name)) }
            }
            let info = EmailInfo(from: m.from, fromName: m.fromName ?? m.from, subject: subject, receivedAt: received)
            // School mail becomes posts for your child (SPEC 7). Nothing for them: nothing kept.
            if SchoolMail.isSchoolMail(from: m.from ?? "", fromName: m.fromName ?? "", subject: subject, text: mailText),
               let made = await SchoolMail.posts(subject: subject, text: mailText,
                                                 files: files.map { SchoolMail.File(name: $0.name ?? "attachment", mime: $0.mime, data: $0.data) },
                                                 email: info, keeper: keeper) {
                _ = made
                done.append(m.id)
                continue
            }
            var draft = Detection.Draft(kind: .note, title: String((subject.isEmpty ? body : subject).prefix(140)), text: String(body.prefix(8000)))
            draft.url = m.links?.first
            let (s, _) = keeper.keep(draft, reason: reason, reasonSource: .email, source: .email, files: files, events: events)
            s.emailFrom = m.from; s.emailFromName = m.fromName ?? m.from; s.emailSubject = subject; s.emailReceivedAt = received
            s.inboxAt = keeper.now()
            done.append(m.id)
        }
        try? keeper.context.save()
        if !done.isEmpty {
            var ack = URLRequest(url: relay.appending(path: "inbox/ack"))
            ack.httpMethod = "POST"
            ack.setValue(key, forHTTPHeaderField: "x-inbox-key")
            ack.setValue("application/json", forHTTPHeaderField: "content-type")
            ack.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": done])
            _ = try? await URLSession.shared.data(for: ack)
        }
        return done.count
    }

    /// The readable text of a public web page, or nil.
    static func pageText(_ link: String) async -> String? {
        guard let url = URL(string: Detection.unwrapLink(link)), url.scheme?.hasPrefix("http") == true else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let text = EmailRules.text(fromHTML: html)
        return text.count > 200 ? String(text.prefix(30000)) : nil
    }

    /// Your words above a forwarded message are the reason; the rest is the email.
    static func split(_ text: String) -> (reason: String, body: String) {
        let markers = ["---------- Forwarded message", "Begin forwarded message:", "-----Original Message-----", "From: "]
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for m in markers {
            if let r = t.range(of: m) {
                let above = t[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let note = above.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("Sent from my") }.joined(separator: " ")
                return (SpokenReason.clip(note), String(t[r.lowerBound...]))
            }
        }
        return ("", t)
    }

    private static func file(mail: String, n: Int, key: String) async -> Data? {
        var c = URLComponents(url: relay.appending(path: "inbox/file"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "id", value: mail), URLQueryItem(name: "n", value: String(n))]
        guard let url = c?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "x-inbox-key")
        req.timeoutInterval = 30
        guard let (data, _) = try? await URLSession.shared.data(for: req), let f = try? JSONDecoder().decode(FilePart.self, from: data),
              let b64 = f.data else { return nil }
        return Data(base64Encoded: b64)
    }
}

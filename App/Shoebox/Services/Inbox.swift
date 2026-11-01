import Foundation
import ShoeboxCore
import SwiftData

/// Your Shoebox email address. Mail waits on the relay up to 30 days until the app collects it.
/// Each email becomes one short post written from what matters in it (the email itself is not kept); your note above a forward is the reason; ads are skipped;
/// a date in the email makes it come back on its own before that day.
@MainActor
enum Inbox {
    private static var running = false

    struct Mail: Decodable {
        var id: String
        var from: String?
        var fromName: String?
        var subject: String?
        var text: String?
        var at: Double?
        var links: [String]?
    }
    struct Response: Decodable { var mails: [Mail]?; var address: String? }
    struct AddressResponse: Decodable { var address: String? }
    struct Problem: Decodable { var error: Message?; struct Message: Decodable { var message: String? } }

    /// A private key that ties this phone to its mailbox on the relay. Made once.
    static var key: String {
        if let k = Prefs.inboxKey { return k }
        let k = "sb-" + (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined().prefix(40)
        Prefs.inboxKey = String(k)
        return String(k)
    }

    /// Asks the relay for an address from your first name. Returns the address or a plain reason it failed.
    static func makeAddress(firstName: String) async -> Result<String, Error> {
        let name = firstName.lowercased().filter { $0.isLetter }
        guard !name.isEmpty else { return .failure(Failure("Type your first name first.")) }
        let body = try? JSONSerialization.data(withJSONObject: ["name": name])
        let req = Relay.request("inbox/address", method: "POST", body: body, key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req) else {
            return .failure(Failure("Couldn't reach Shoebox's server. Try again in a minute."))
        }
        if (res as? HTTPURLResponse)?.statusCode == 200, let a = try? JSONDecoder().decode(AddressResponse.self, from: data).address {
            Prefs.inboxAddress = a
            return .success(a)
        }
        let message = (try? JSONDecoder().decode(Problem.self, from: data))?.error?.message
        return .failure(Failure(message ?? "Couldn't make an address right now."))
    }

    struct Failure: LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    @discardableResult
    static func collect(_ context: ModelContext) async -> Int {
        guard !running, let key = Prefs.inboxKey else { return 0 }
        running = true
        defer { running = false }
        let req = Relay.request("inbox", key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return 0 }
        if let a = r.address { Prefs.inboxAddress = a }
        let existing = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        var done: [String] = []
        var added = 0
        let now = Date()
        for m in r.mails ?? [] {
            let subject = (m.subject ?? "").replacingOccurrences(of: #"^((re|fwd?|fw):\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
            let received = m.at.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
            // The same message twice: keep one.
            if existing.contains(where: { $0.emailSubject == subject && $0.emailFrom == m.from
                && abs(($0.emailReceivedAt ?? .distantPast).timeIntervalSince(received)) < 2 * 86_400 }) {
                done.append(m.id); continue
            }
            let (reason, rawBody) = split(m.text ?? "")
            // Promotional mail makes no post unless you wrote a note above it (USPS Informed Delivery included).
            if EmailRules.kind(from: m.from ?? "", fromName: m.fromName ?? "", subject: subject, text: m.text ?? "", hasOwnNote: !reason.isEmpty) == .promotional {
                done.append(m.id); continue
            }
            let body = EmailRules.stripAds(rawBody)
            let firstLines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("From:") && !$0.hasPrefix("Date:") && !$0.hasPrefix("Subject:") && !$0.hasPrefix("To:") && !$0.contains("Forwarded message") }
            // The post is what matters in the email, written on the phone. The email itself is not kept.
            let written = await EmailPost.write(subject: subject, lines: firstLines)
            let s = Save(title: String(written.title.prefix(140)),
                         snippet: String(written.text.replacingOccurrences(of: "\n", with: " ").prefix(240)),
                         body: written.text, note: reason,
                         origin: "via your Shoebox email", kind: .email, createdAt: received)
            s.urlString = m.links?.first(where: { !$0.lowercased().contains("unsubscribe") }).map(Detection.unwrapLink)
            s.enrichedAt = now
            s.emailFrom = m.from
            s.emailSubject = subject
            s.emailReceivedAt = received
            // A date in the email: it comes back 5 days before, the day before and on the day.
            let days = EmailRules.days(in: subject + "\n" + firstLines.joined(separator: "\n"), received: received, calendar: .current).filter { $0 > now }.sorted()
            if let day = days.first {
                s.eventDate = day
                if let first = SaveActions().reminders(for: day).first(where: { $0 > now }) {
                    s.status = .away
                    s.returnDate = first
                } else {
                    s.status = .today
                }
            } else {
                Capture.place(s, note: reason, now: now)
            }
            context.insert(s)
            added += 1
            done.append(m.id)
        }
        try? context.save()
        if !done.isEmpty {
            let body = try? JSONSerialization.data(withJSONObject: ["ids": done])
            _ = try? await URLSession.shared.data(for: Relay.request("inbox/ack", method: "POST", body: body, key: key))
        }
        return added
    }

    /// Your words above a forwarded message are the reason; the rest is the email.
    static func split(_ text: String) -> (reason: String, body: String) {
        let markers = ["---------- Forwarded message", "Begin forwarded message:", "-----Original Message-----", "From: "]
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for m in markers {
            if let r = t.range(of: m) {
                let above = t[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let note = above.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("Sent from my") }.joined(separator: " ")
                return (SpokenReason.clip(note), String(t[r.lowerBound...]))
            }
        }
        return ("", t)
    }
}

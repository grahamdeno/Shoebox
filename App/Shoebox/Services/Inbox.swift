import Foundation
import ShoeboxCore
import SwiftData

/// Your Shoebox email address. Mail waits on the relay up to 7 days until the app collects it.
/// Each email becomes one short post written from what matters in it (the email itself is not kept); your note above a forward is the reason;
/// ads and sign-in codes are skipped; a PDF or a lone link is read too; a date makes it come back before that day; an email with many
/// dates (a school newsletter) becomes one post per date that is about the people named in Settings.
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
        var attachments: [Attachment]?
    }
    struct Attachment: Decodable { var n: Int; var name: String?; var type: String?; var size: Int? }
    struct FileResponse: Decodable { var data: String? }
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
        // Dated posts already made from email (and in this collection), so a newsletter sent again each week
        // does not make the same event twice.
        var known = existing.filter { $0.deletedAt == nil && $0.kind == .email && $0.eventDate != nil }
        for m in r.mails ?? [] {
            let subject = EmailRules.cleanSubject(m.subject ?? "")
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
            // Sign-in codes and account notices: never a post.
            if reason.isEmpty, EmailRules.isAccountNotice(subject: subject, text: m.text ?? "") {
                done.append(m.id); continue
            }
            let body = EmailRules.stripAds(EmailRules.unwrap(rawBody))
            var lines = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !EmailRules.isForwardHeader($0) }
            let link = m.links?.first(where: { !$0.lowercased().contains("unsubscribe") }).map(Detection.unwrapLink)

            // A PDF sent by email is read like the email itself, and kept on the post so you can open it.
            var pdf: (data: Data, name: String, picture: Data?)?
            if let a = m.attachments?.first(where: { ($0.type ?? "").contains("pdf") }), let data = await attachment(mail: m.id, n: a.n, key: key) {
                let read = await Task.detached { FileKeeper.pdf(data) }.value
                pdf = (data, FileKeeper.safeName(a.name ?? "attachment.pdf"), read?.picture)
                if let text = read?.text, !text.isEmpty { lines += text.components(separatedBy: .newlines) }
            }
            // An email that is only a link ("have a look at this"): read the page, so the post is about it.
            let thin = lines.filter { !$0.hasPrefix("http") }.joined(separator: " ").count < 120
            if thin, pdf == nil, let link, let url = URL(string: link), let text = await Relay.preview(url)?.text, !text.isEmpty {
                lines += EmailRules.unwrap(text).components(separatedBy: "\n").prefix(400)
            }

            // Many dates (a school newsletter, a season schedule): one post per date that is about your people.
            let items = EmailCalendar.items(in: lines.joined(separator: "\n"), received: received, calendar: .current, dayFirst: EmailCalendar.deviceDayFirst)
            if items.count >= EmailCalendar.minimumDates {
                let today = Calendar.current.startOfDay(for: now)
                let keep = EmailCalendar.relevant(items, to: EmailCalendar.Profile(Prefs.mailFor)).filter { $0.day >= today }
                for item in keep {
                    let words = EmailCalendar.details(of: item, received: received, calendar: .current)
                    if let old = known.first(where: { Calendar.current.isDate($0.eventDate ?? .distantPast, inSameDayAs: item.day)
                        && EmailCalendar.sameEvent($0.title, item.title) }) {
                        refresh(old, with: words, now: now)
                        continue
                    }
                    // Where it came from goes in the byline ("You, today, from Roosevelt newsletter"), not the words.
                    let s = Save(title: String(item.title.prefix(140)), snippet: String(words.prefix(240)), body: words,
                                 note: reason, origin: EmailCalendar.sourceName(subject), kind: .email, createdAt: received)
                    s.urlString = (item.link?.absoluteString).map(Detection.unwrapLink)
                    stamp(s, mail: m, subject: subject, received: received, now: now)
                    schedule(s, on: item.day, now: now)
                    context.insert(s)
                    known.append(s)
                    added += 1
                }
                done.append(m.id)
                continue
            }

            // The post is what matters in the email, written on the phone. The email itself is not kept.
            let written = await EmailPost.write(subject: subject, lines: lines, received: received, reader: readerName)
            // A post about a date leads with that day, so it never comes back for the wrong Thursday.
            let when = EmailRules.days(in: subject + "\n" + lines.joined(separator: "\n"), received: received, calendar: .current)
                .filter { $0 > now }.min()
            let text = EmailRules.leadWithDay(written.text, day: when, calendar: .current)
            let s = Save(title: String(written.title.prefix(140)),
                         snippet: String(text.replacingOccurrences(of: "\n", with: " ").prefix(240)),
                         body: text, note: reason,
                         origin: "via your Shoebox email", kind: .email, createdAt: received)
            s.urlString = link
            stamp(s, mail: m, subject: subject, received: received, now: now)
            if let pdf {
                s.fileData = pdf.data
                s.fileName = pdf.name
                s.fileType = "com.adobe.pdf"
                if let picture = pdf.picture { s.imageData = picture; s.imageSource = "photo" }
            } else if thin, link != nil {
                // Only a link: let the page's own picture come in later, as for a shared link.
                s.enrichedAt = nil
            }
            // A date in the email: seen now, then back 5 days before and every day until put away.
            let days = EmailRules.days(in: subject + "\n" + lines.joined(separator: "\n"), received: received, calendar: .current).filter { $0 > now }.sorted()
            if let day = days.first {
                schedule(s, on: day, now: now)
            } else {
                Capture.place(s, note: reason, now: now)
            }
            context.insert(s)
            added += 1
            done.append(m.id)
        }
        // Mail is acknowledged (and so deleted from the relay) only after the posts made from it are saved.
        // If the save fails, the new posts are dropped and the mail stays on the relay for the next try.
        let saved = await commit(done: done, save: { try context.save() }, acknowledge: { ids in
            let body = try? JSONSerialization.data(withJSONObject: ["ids": ids])
            _ = try? await URLSession.shared.data(for: Relay.request("inbox/ack", method: "POST", body: body, key: key))
        })
        if !saved {
            context.rollback()
            return 0
        }
        return added
    }

    /// Saves, then acknowledges the mail that was handled. Returns false, without acknowledging anything,
    /// when the save fails: the mail then waits on the relay and is collected again.
    static func commit(done: [String], save: () throws -> Void, acknowledge: ([String]) async -> Void) async -> Bool {
        do { try save() } catch { return false }
        if !done.isEmpty { await acknowledge(done) }
        return true
    }

    /// The first name in your address ("Sam-keep@..." gives "Sam"), so posts can say "you". Empty when unknown.
    private static var readerName: String {
        guard let local = Prefs.inboxAddress?.split(separator: "@").first else { return "" }
        let name = local.split(separator: "-").first.map { String($0.filter(\.isLetter)) } ?? ""
        return name.count >= 2 ? name.prefix(1).uppercased() + name.dropFirst().lowercased() : ""
    }

    private static func stamp(_ s: Save, mail m: Mail, subject: String, received: Date, now: Date) {
        s.enrichedAt = now
        s.emailFrom = m.from
        s.emailSubject = subject
        s.emailReceivedAt = received
    }

    /// Seen once when it arrives; flicked up, it waits for 5 days before, then is back every day until put away.
    private static func schedule(_ s: Save, on day: Date, now: Date) {
        s.eventDate = day
        s.status = .today
        s.returnDate = nil
    }

    /// The same event sent again. New details replace the old words quietly; a new time shows it once more,
    /// even if it was put away, with what changed on top. Otherwise a put away post stays put away.
    private static func refresh(_ s: Save, with words: String, now: Date) {
        let old = s.body.components(separatedBy: "\n").filter { !$0.hasPrefix("Changed:") && !$0.isEmpty }.joined(separator: " ")
        guard old != words else { return }
        if let change = EmailCalendar.timeChange(from: old, to: words) {
            s.body = "Changed: \(change).\n" + words
            s.status = .today
            s.returnDate = nil
            s.seenOn = nil
        } else {
            s.body = words
        }
        s.snippet = String(words.prefix(240))
        s.updatedAt = now
    }

    /// One attachment of a waiting mail, fetched before the mail is acknowledged (which deletes it).
    private static func attachment(mail id: String, n: Int, key: String) async -> Data? {
        let req = Relay.request("inbox/file", query: [.init(name: "id", value: id), .init(name: "n", value: String(n))], key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let b64 = try? JSONDecoder().decode(FileResponse.self, from: data).data else { return nil }
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
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

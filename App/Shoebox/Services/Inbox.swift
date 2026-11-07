import CryptoKit
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

    /// One mail as the relay hands it over. A sealed record (`v` 1) carries only `enc` and `ct`; everything else is inside
    /// them. A record without `v` is plain mail from before sealing, read as it is until 1.1 (see `opened`).
    struct Mail: Decodable {
        var id: String
        var v: Int?
        var enc: String?
        var ct: String?
        var from: String?
        var fromName: String?
        var subject: String?
        var text: String?
        var at: Double?
        var links: [String]?
        var attachments: [Attachment]?
    }
    struct Attachment: Decodable { var n: Int; var name: String?; var type: String?; var size: Int? }
    /// A sealed attachment comes as `v`, `enc` and `ct`; a plain one from before sealing as `data` (base64).
    struct FileResponse: Decodable { var data: String?; var v: Int?; var enc: String?; var ct: String? }
    /// `pub` is the sealing key the relay holds for this phone's mailbox, so the phone can tell when to register its own.
    struct Response: Decodable { var mails: [Mail]?; var address: String?; var pub: String? }
    struct AddressResponse: Decodable { var address: String? }
    struct Problem: Decodable { var error: Message?; struct Message: Decodable { var message: String? } }

    /// Asks the relay for an address from your first name, with this phone's sealing key and StoreKit's signed proof of
    /// Shoebox Plus (or, in TestFlight and review, of the install). Returns the address or a plain reason it failed.
    static func makeAddress(firstName: String, testerCode: String = "") async -> Result<String, Error> {
        let name = firstName.lowercased().filter { $0.isLetter }
        guard !name.isEmpty else { return .failure(Failure("Type your first name first.")) }
        // A tester code typed now is kept to use; if it fails, it is forgotten again so a wrong one doesn't stay.
        let typedCode = testerCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedCode.isEmpty { MailboxKeys.setTesterCode(typedCode) }
        guard let access = await Plus.access(refresh: true) else {
            return .failure(Failure(Plus.inSandbox
                ? "Couldn't confirm this is a TestFlight copy. Type the tester code you were given, or tap Buy Shoebox Plus below (free in TestFlight)."
                : "Shoebox Plus is needed to get an address."))
        }
        // The private key that ties this phone to its mailbox, and the sealing key, both kept in the Keychain.
        guard let key = MailboxKeys.secretMakingOne(), let pub = MailboxKeys.sealingPublicKey() else {
            return .failure(Failure("Couldn't save this phone's key. Try again in a minute."))
        }
        let body = try? JSONSerialization.data(withJSONObject: ["name": name, "pub": pub, access.field.key: access.field.value])
        let req = Relay.request("inbox/address", method: "POST", body: body, key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req) else {
            return .failure(Failure("Couldn't reach Shoebox's server. Try again in a minute."))
        }
        if (res as? HTTPURLResponse)?.statusCode == 200, let a = try? JSONDecoder().decode(AddressResponse.self, from: data).address {
            Prefs.inboxAddress = a
            Prefs.sealingRegistered = true
            Prefs.sealMismatchSince = nil
            return .success(a)
        }
        if !typedCode.isEmpty, (res as? HTTPURLResponse)?.statusCode != 200 { MailboxKeys.setTesterCode("") }
        let message = (try? JSONDecoder().decode(Problem.self, from: data))?.error?.message
        return .failure(Failure(message ?? "Couldn't make an address right now."))
    }

    struct Failure: LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    /// `forceSealing`: Settings › Restore purchases, where the person asks for this phone's key to be the one.
    @discardableResult
    static func collect(_ context: ModelContext, forceSealing: Bool = false) async -> Int {
        // A Keychain that can't be read right now: try again later, and never make a key over the one that's there.
        guard !running, let key = MailboxKeys.secret() else { return 0 }
        if case .failed = MailboxKeys.sealingKeyState() { return 0 }
        running = true
        defer { running = false }
        let req = Relay.request("inbox", key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return 0 }
        // No address on the server (a new relay, or it expired): stop showing one that no longer delivers.
        Prefs.inboxAddress = r.address
        let sealing = await settleSealing(held: r.pub, hasAddress: r.address != nil, key: key, force: forceSealing)
        let box = MailboxKeys.boxID(for: key)
        var unopened = 0
        // Posts made in this collection are added as they are made, so two copies in one batch are caught too.
        var existing = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        var done: [String] = []
        var added = 0
        let now = Date()
        // Dated posts already made from email (and in this collection), so a newsletter sent again each week
        // does not make the same event twice.
        var known = existing.filter { $0.deletedAt == nil && $0.kind == .email && $0.eventDate != nil }
        for stored in r.mails ?? [] {
            // A version this build does not know is left on the relay for a newer build, not counted or acknowledged.
            if let v = stored.v, v != 1 { continue }
            // Sealed to a key this phone does not have yet. It may still be on its way through iCloud Keychain, so the
            // mail stays on the relay for 2 days. After that it is counted and acknowledged, so it can't block newer mail.
            guard let m = opened(stored, box: box, key: sealing) else {
                if mayDropUnopened(at: stored.at, now: now) { unopened += 1; done.append(stored.id) }
                continue
            }
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
            if let a = m.attachments?.first(where: { ($0.type ?? "").contains("pdf") }), let data = await attachment(mail: m.id, n: a.n, key: key, box: box, sealing: sealing) {
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
            // The same post made twice (one notice forwarded twice, or by two people): keep the first. Only the same
            // title AND the same words count, so next week's newsletter with last week's title is still kept.
            if isRepeat(title: written.title, text: text, received: received, in: existing) {
                done.append(m.id); continue
            }
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
            existing.append(s)
            added += 1
            done.append(m.id)
        }
        // Mail is acknowledged (and so deleted from the relay) only after the posts made from it are saved.
        // If the save fails, the mail stays on the relay for the next try. The context is not rolled back: it is the
        // app's main context, and a rollback would also throw away anything else not yet saved, such as an edit.
        // If the new posts are saved later, the next collection finds them and does not make them twice.
        let saved = await commit(done: done, save: { try context.save() }, acknowledge: { ids in
            let body = try? JSONSerialization.data(withJSONObject: ["ids": ids])
            _ = try? await URLSession.shared.data(for: Relay.request("inbox/ack", method: "POST", body: body, key: key))
        })
        if unopened > 0 { noteUnopened(unopened) }
        if !saved { return 0 }
        return added
    }

    // MARK: Sealed mail

    /// A mail as the relay stored it, made readable. A record without a version is plain mail from before sealing and is
    /// read as it is. Nil when it is sealed to a key this phone does not have, or is a version this build does not know.
    static func opened(_ m: Mail, box: String, key: Curve25519.KeyAgreement.PrivateKey?) -> Mail? {
        guard let v = m.v else { return m }
        guard v == 1, let key,
              let data = SealedMail.openBase64(enc: m.enc, ct: m.ct, aad: "\(box):\(m.id)", with: key),
              let body = try? JSONDecoder().decode(SealedMail.Opened.self, from: data) else { return nil }
        return Mail(id: m.id, from: body.from, fromName: body.fromName, subject: body.subject, text: body.text,
                    at: m.at, links: body.links, attachments: body.attachments)
    }

    /// How long mail this phone can't open stays on the relay before it is given up on.
    static let keepUnopened: TimeInterval = 2 * 86_400

    /// `at` is when the relay stored the mail, in milliseconds. Without one, the relay's own 7 days decide.
    static func mayDropUnopened(at: Double?, now: Date) -> Bool {
        guard let at else { return false }
        return now.timeIntervalSince1970 - at / 1000 >= keepUnopened
    }

    /// Counts mail that could not be opened. After a week with none, the count starts again.
    static func noteUnopened(_ n: Int, now: Date = Date()) {
        let recent = Prefs.unopenedMailAt.map { now.timeIntervalSince($0) < 7 * 86_400 } ?? false
        Prefs.unopenedMail = (recent ? Prefs.unopenedMail : 0) + n
        Prefs.unopenedMailAt = now
    }

    /// The one quiet line Settings › Email shows ("1 email couldn't be opened on this phone."), or nil.
    static func unopenedLine(now: Date = Date()) -> String? {
        guard let at = Prefs.unopenedMailAt, now.timeIntervalSince(at) < 7 * 86_400, Prefs.unopenedMail > 0 else { return nil }
        let n = Prefs.unopenedMail
        return n == 1 ? "1 email couldn't be opened on this phone." : "\(n) emails couldn't be opened on this phone."
    }

    /// What to do about the sealing key the relay holds for this phone's address.
    enum SealingStep: Equatable {
        case ready      // the relay holds this phone's key
        case register   // register this phone's key now
        case wait       // the relay holds another key: give this phone's own time to arrive
    }

    /// How long a phone waits, when the relay holds a key it doesn't have, before registering its own.
    static let sealingGrace: TimeInterval = 86_400

    /// The rule. The relay holding no key means no mail is sealed to anything, so registering loses nothing. The relay
    /// holding another key usually means this phone's copy is still coming through iCloud Keychain, or another phone
    /// on the same Apple Account has it: registering at once would seal mail to a key the other phone doesn't have.
    /// So the phone waits a day, unless the person asks (Restore purchases).
    static func sealingStep(held: String?, mine: String?, mismatchSince: Date?, now: Date, force: Bool) -> SealingStep {
        if let mine, held == mine { return .ready }
        if held == nil || force { return .register }
        if let since = mismatchSince, now.timeIntervalSince(since) >= sealingGrace { return .register }
        return .wait
    }

    /// Settles the sealing key with the relay and returns the key to open mail with (nil when this phone has none).
    /// A key is made only when it is about to be registered. The relay decides whether it takes it: with Plus, or for
    /// the owner's own address before Plus is on sale. Otherwise the mail waits and Settings says so. Quiet: it never
    /// asks the person for anything.
    static func settleSealing(held: String?, hasAddress: Bool, key: String, force: Bool, now: Date = Date()) async -> Curve25519.KeyAgreement.PrivateKey? {
        var mine: Curve25519.KeyAgreement.PrivateKey?
        if case .found(let k) = MailboxKeys.sealingKeyState() { mine = k }
        guard hasAddress else { return mine }
        switch sealingStep(held: held, mine: mine.map(MailboxKeys.publicText), mismatchSince: Prefs.sealMismatchSince, now: now, force: force) {
        case .ready:
            Prefs.sealingRegistered = true
            Prefs.sealMismatchSince = nil
            return mine
        case .wait:
            Prefs.sealingRegistered = false
            if Prefs.sealMismatchSince == nil { Prefs.sealMismatchSince = now }
            return mine
        case .register:
            Prefs.sealingRegistered = false
            if held != nil, Prefs.sealMismatchSince == nil { Prefs.sealMismatchSince = now }
            // Without Plus the relay still answers for the owner's own address (PLUS_OWNER_ADDRESS) and says 402 to
            // anyone else, so the phone asks either way. A key is made only when the relay holds none, or after the
            // wait (above), so asking without Plus never replaces a key that works.
            guard let sealing = mine ?? MailboxKeys.sealingKey() else { return mine }
            let field = await Plus.access()?.field ?? (key: "purchase", value: "")
            let body = try? JSONSerialization.data(withJSONObject: ["pub": MailboxKeys.publicText(sealing), field.key: field.value])
            let req = Relay.request("inbox/seal", method: "POST", body: body, key: key)
            if let (_, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200 {
                Prefs.sealingRegistered = true
                Prefs.sealMismatchSince = nil
            }
            return sealing
        }
    }

    // MARK: Delete everything that finishes (D-6)

    /// Asks the relay to forget the mailbox that Delete everything took away, and keeps asking until it confirms: on
    /// every launch and every return to the app. The request is safe to repeat. Returns true when nothing is left to
    /// remove. Only the relay's own answers end it: a 200 that says `{"ok":true}`, or a 401 with the relay's error
    /// (it refuses the key's shape, so it can hold nothing for it). A Wi-Fi sign-in page that answers 200 does not.
    @discardableResult
    static func finishPendingDelete(send: (URLRequest) async -> (status: Int?, body: Data?) = Inbox.responseOf) async -> Bool {
        guard let secret = MailboxKeys.pendingDelete() else { return true }
        let answer = await send(Relay.request("me/delete", method: "POST", body: Data("{}".utf8), key: secret))
        guard relayConfirmedDelete(status: answer.status, body: answer.body) else { return false }
        MailboxKeys.finishDelete()
        return true
    }

    static func relayConfirmedDelete(status: Int?, body: Data?) -> Bool {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        switch status {
        case 200: return object["ok"] as? Bool == true
        case 401: return (object["error"] as? [String: Any])?["message"] is String
        default: return false
        }
    }

    nonisolated static func responseOf(_ request: URLRequest) async -> (status: Int?, body: Data?) {
        guard let (data, res) = try? await URLSession.shared.data(for: request) else { return (nil, nil) }
        return ((res as? HTTPURLResponse)?.statusCode, data)
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

    /// One attachment of a waiting mail, fetched before the mail is acknowledged (which deletes it). A sealed one is
    /// opened here; a plain one from before sealing is just decoded.
    private static func attachment(mail id: String, n: Int, key: String, box: String, sealing: Curve25519.KeyAgreement.PrivateKey?) async -> Data? {
        let req = Relay.request("inbox/file", query: [.init(name: "id", value: id), .init(name: "n", value: String(n))], key: key)
        guard let (data, res) = try? await URLSession.shared.data(for: req), (res as? HTTPURLResponse)?.statusCode == 200,
              let file = try? JSONDecoder().decode(FileResponse.self, from: data) else { return nil }
        if let v = file.v {
            guard v == 1, let sealing else { return nil }
            return SealedMail.openBase64(enc: file.enc, ct: file.ct, aad: "\(box):\(id):\(n)", with: sealing)
        }
        guard let b64 = file.data else { return nil }
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    }

    /// A post from email that already exists: same title, same opening words, within two weeks.
    static func isRepeat(title: String, text: String, received: Date, in existing: [Save]) -> Bool {
        let opening = { (t: String) in String(t.replacingOccurrences(of: "\n", with: " ").prefix(160)).lowercased() }
        let mine = opening(text)
        return existing.contains { s in
            s.deletedAt == nil && s.kind == .email
                && s.title.caseInsensitiveCompare(String(title.prefix(140))) == .orderedSame
                && opening(s.body) == mine
                && abs((s.emailReceivedAt ?? s.createdAt).timeIntervalSince(received)) < 14 * 86_400
        }
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

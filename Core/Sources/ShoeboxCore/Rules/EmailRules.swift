import Foundation

/// SPEC 7.6: sort email before any AI sees it, cut ads, and check what the AI returns against the email.
public enum EmailRules {
    public enum Kind: Sendable, Equatable { case promotional, other }

    /// Senders whose mail is never worth a post on its own.
    static let promoSenders = ["informeddelivery", "usps.com", "marketing", "promo", "deals", "offers", "newsletter@", "news@"]
    static let promoWords = ["unsubscribe", "% off", "shop now", "limited time", "sale ends", "coupon", "promo code",
                             "free shipping", "view in browser", "view this email in your browser", "deal", "save up to",
                             "sponsored", "advertisement", "buy now", "order now", "exclusive offer"]

    /// Promotional when the sender is a known mailer or the text carries at least three promotion signals.
    /// A note of your own above a forward always keeps it (you chose it).
    public static func kind(from: String, fromName: String, subject: String, text: String, hasOwnNote: Bool) -> Kind {
        if hasOwnNote { return .other }
        let sender = (from + " " + fromName).lowercased()
        if promoSenders.contains(where: { sender.contains($0) }) { return .promotional }
        let t = (subject + "\n" + text).lowercased()
        let hits = promoWords.filter { t.contains($0) }.count
        return hits >= 3 ? .promotional : .other
    }

    /// Email text as plain lines: Windows line ends made plain (Swift reads "\r\n" as one character, so a
    /// split on "\n" missed every line), "format=flowed" soft breaks (a line ending in a space) joined back up,
    /// and the common HTML entities decoded.
    public static func unwrap(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: #" \n(?!\n)"#, with: " ", options: .regularExpression)
        for (e, v) in ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
                       "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&lt;": "<", "&gt;": ">", "&ndash;": "-", "&mdash;": "-", "&#160;": " "] {
            s = s.replacingOccurrences(of: e, with: v)
        }
        return s
    }

    /// Sign-in codes and account notices: useful for minutes, never worth a post.
    public static func isAccountNotice(subject: String, text: String) -> Bool {
        let t = (subject + "\n" + text.prefix(1_500)).lowercased()
        let signs = ["verification code", "security code", "one-time code", "one time code", "one-time password", "passcode",
                     "your code is", "confirmation code is", "login code", "sign-in code", "sign in code", "2-step", "two-factor",
                     "new sign-in", "new sign in", "new login", "sign-in attempt", "login attempt", "reset your password",
                     "password reset", "verify your email", "confirm your email address"]
        return signs.contains(where: t.contains)
    }

    /// A subject without the clutter in front: "[List] Fwd: Fwd: Re: Dock quote" gives "Dock quote".
    public static func cleanSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            let before = s
            s = s.replacingOccurrences(of: #"^\[[^\]]{0,60}\]\s*"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"^(re|fwd?|fw|aw|wg)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            if s == before { break }
        }
        return s
    }

    /// True when a written post holds something the email does not: a number that is not in it, or a day
    /// word (today, tomorrow, tonight) the email never used. Such a post is not used.
    public static func invents(_ post: String, source: String) -> Bool {
        let sourceNumbers = numbers(in: source)
        if numbers(in: post).contains(where: { !sourceNumbers.contains($0) }) { return true }
        let p = post.lowercased(), src = source.lowercased()
        for w in ["today", "tomorrow", "tonight", "this morning", "this afternoon", "this evening", "this weekend"]
            where p.contains(w) && !src.contains(w) { return true }
        return false
    }

    static func numbers(in text: String) -> Set<String> {
        var out = Set<String>()
        var run = ""
        for ch in text {
            if ch.isASCII, ch.isNumber { run.append(ch) } else {
                if !run.isEmpty { out.insert(String(run.drop { $0 == "0" }.isEmpty ? "0" : run.drop { $0 == "0" })) }
                run = ""
            }
        }
        if !run.isEmpty { out.insert(String(run.drop { $0 == "0" }.isEmpty ? "0" : run.drop { $0 == "0" })) }
        return out
    }

    /// Cuts ad blocks: lines that sell, sponsor sections, and everything from the unsubscribe footer down.
    public static func stripAds(_ text: String) -> String {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.lowercased()
            if line.contains("unsubscribe") || line.contains("manage your preferences") || line.contains("view this email in your browser")
                || line.contains("you are receiving this") { break }
            if ["sponsored", "advertisement", "shop now", "buy now", "% off", "promo code", "coupon", "limited time", "order now"]
                .contains(where: { line.contains($0) }) { continue }
            out.append(raw)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A post that reads like an ad.
    public static func looksLikePromotion(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["% off", "shop now", "buy now", "limited time", "promo code", "coupon", "sponsored by", "order now", "free shipping"]
            .contains(where: { t.contains($0) })
    }

    /// True when most of the quote's words appear in the text, so a post can be traced to its line.
    public static func quoteFound(_ quote: String, in text: String) -> Bool {
        let words = normalize(quote).split(separator: " ").filter { $0.count > 3 }
        guard !words.isEmpty else { return false }
        let hay = normalize(text)
        let found = words.filter { hay.contains($0) }.count
        return Double(found) / Double(words.count) >= 0.7
    }

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let kept = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Days the email itself names: written dates, and weekdays within the two weeks after it arrived.
    public static func days(in text: String, received: Date, calendar: Calendar) -> Set<Date> {
        var out = Set<Date>()
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let d = m.date { out.insert(calendar.startOfDay(for: d)) }
            }
        }
        let lower = text.lowercased()
        let names = calendar.weekdaySymbols.map { $0.lowercased() }
        for add in 0...14 {
            guard let d = calendar.date(byAdding: .day, value: add, to: received) else { continue }
            let w = calendar.component(.weekday, from: d)
            if lower.contains(names[w - 1]) { out.insert(calendar.startOfDay(for: d)) }
        }
        // Month-day pairs written without a year ("Nov 20", "November 20th") resolve to the next such day.
        let months = calendar.shortMonthSymbols.map { $0.lowercased() }
        let scanner = lower.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ")
        let tokens = scanner.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        for (i, tok) in tokens.enumerated() where i + 1 < tokens.count {
            guard let mi = months.firstIndex(where: { tok.hasPrefix($0) }) else { continue }
            let digits = tokens[i + 1].prefix { $0.isNumber }
            guard let day = Int(digits), (1...31).contains(day) else { continue }
            var c = calendar.dateComponents([.year], from: received)
            c.month = mi + 1; c.day = day
            if var d = calendar.date(from: c) {
                if d < calendar.date(byAdding: .day, value: -60, to: received) ?? received {
                    d = calendar.date(byAdding: .year, value: 1, to: d) ?? d
                }
                out.insert(calendar.startOfDay(for: d))
            }
        }
        return out
    }

    /// Plain text from a web page: scripts and styles removed, block tags as line breaks, common entities decoded.
    public static func text(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (e, v) in ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
                       "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&lt;": "<", "&gt;": ">", "&ndash;": "-", "&mdash;": "-"] {
            s = s.replacingOccurrences(of: e, with: v)
        }
        let lines = s.components(separatedBy: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

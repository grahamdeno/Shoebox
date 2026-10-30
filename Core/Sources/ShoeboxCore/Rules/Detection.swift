import Foundation

/// What arrived, decided without asking (docs/SPEC.md 2.1 and 2.2).
/// Ported from the old app's model.js `detectText`, `draftFromUrl`, `parseQuote`, `kindOfFile`,
/// `youtubeId`, `titleFromUrl`, and ai.js `unwrapLink`.
public enum Detection {
    public struct Draft: Sendable, Equatable {
        public var kind: SaveKind
        public var title: String
        public var text: String?
        public var url: String?
        public var author: String?
        public var videoId: String?
        public var imageURL: String?

        public init(kind: SaveKind, title: String, text: String? = nil, url: String? = nil,
                    author: String? = nil, videoId: String? = nil, imageURL: String? = nil) {
            self.kind = kind; self.title = title; self.text = text; self.url = url
            self.author = author; self.videoId = videoId; self.imageURL = imageURL
        }
    }

    // MARK: Patterns, kept as close to the old JavaScript as ICU allows.

    static let urlPattern = "\\bhttps?://[^\\s<>\"']+"
    static let urlTailPattern = "[).,;:!?\\]]+$"
    static let youTubePattern = "(?:youtube\\.com/(?:watch\\?(?:[^#\\s]*&)?v=|shorts/|embed/|live/)|youtu\\.be/)([A-Za-z0-9_-]{11})"
    static let imageURLPattern = "\\.(?:jpe?g|png|gif|webp|avif|heic)(?:[?#].*)?$"
    static let videoURLPattern = "\\.(?:mp4|mov|m4v|webm)(?:[?#].*)?$"
    /// Straight, curly and guillemet quote marks, for use inside a character class.
    static let quoteMarks = "\"'\u{201C}\u{201D}\u{2018}\u{2019}\u{00AB}\u{00BB}"
    static let notAuthorsPattern = "^(?:(?:mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)(?:day)?|today|tomorrow|tonight|jan(?:uary)?|feb(?:ruary)?|march|mar|april|apr|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|asap|eod|tbd)\\b"

    // MARK: Text

    /// One draft per thing in the text; several bare links give several drafts. Empty text gives none.
    public static func drafts(fromText raw: String) -> [Draft] {
        let text = RulesRegex.trim(raw.replacingOccurrences(of: "\r\n", with: "\n"))
        if text.isEmpty { return [] }
        let urls = RulesRegex.strings(urlPattern, in: text, options: [.caseInsensitive])
        // Only links, separated by spaces, commas, dashes or bullets: one save each.
        if urls.count > 1 {
            var leftover = text
            for u in urls {
                if let r = leftover.range(of: u) { leftover.replaceSubrange(r, with: "") }
            }
            leftover = RulesRegex.replace("[\\s,;\\-\u{2022}*]+", in: leftover, with: "")
            if leftover.isEmpty { return urls.map { draft(fromURLString: trimURLTail($0), note: "") } }
        }
        let url = findURL(text)
        var rest = text
        if !url.isEmpty {
            if let r = rest.range(of: url) { rest.replaceSubrange(r, with: "") }
            rest = RulesRegex.trim(rest)
        }
        if !url.isEmpty && rest.count < 40 { return [draft(fromURLString: url, note: rest)] }
        // A link with its page title on one line, the way Safari and other apps share it.
        if !url.isEmpty && rest.count <= 200 && !RulesRegex.hasNewline(rest)
            && text.components(separatedBy: "\n").count <= 2
            && (text.hasPrefix(url) || text.hasSuffix(url)) {
            return [draft(fromURLString: url, note: rest)]
        }
        if let quote = parseQuote(text) {
            return [Draft(kind: .quote, title: firstLine(quote.text), text: quote.text,
                          author: quote.author.isEmpty ? nil : quote.author)]
        }
        return [Draft(kind: .note, title: firstLine(text), text: text, url: url.isEmpty ? nil : url)]
    }

    /// A single link. `title` is the page title or the words that came with it; nil or empty falls
    /// back to the last part of the path, cleaned, or the host.
    public static func draft(fromURL url: URL, title: String?) -> Draft {
        draft(fromURLString: url.absoluteString, note: title ?? "")
    }

    static func draft(fromURLString raw: String, note rawNote: String) -> Draft {
        // [Check] The old detectText did not unwrap; 2.0 unwraps Safe Links and redirects on every link,
        // so a pasted Outlook link saves the real address.
        let url = unwrapLink(raw)
        let note = RulesRegex.trim(rawNote)
        let text: String? = note.isEmpty ? nil : note
        if let id = youTubeId(url) {
            return Draft(kind: .video, title: note.isEmpty ? "YouTube video" : note, text: text, url: url,
                         videoId: id, imageURL: youTubeThumb(id))
        }
        let title = note.isEmpty ? titleFromURL(url) : note
        if RulesRegex.test(imageURLPattern, url, options: [.caseInsensitive]) {
            return Draft(kind: .photo, title: title, text: text, url: url, imageURL: url)
        }
        if RulesRegex.test(videoURLPattern, url, options: [.caseInsensitive]) {
            return Draft(kind: .video, title: title, text: text, url: url)
        }
        return Draft(kind: .link, title: title, text: text, url: url)
    }

    /// First link in the text with trailing punctuation trimmed, or "".
    static func findURL(_ text: String) -> String {
        guard let m = RulesRegex.first(urlPattern, in: text, options: [.caseInsensitive]),
              let u = RulesRegex.group(m, 0, in: text) else { return "" }
        return trimURLTail(u)
    }

    static func trimURLTail(_ u: String) -> String { RulesRegex.replace(urlTailPattern, in: u, with: "") }

    // MARK: YouTube

    /// The 11-character video id from any YouTube URL shape, or nil.
    public static func youTubeId(_ url: String) -> String? {
        guard let m = RulesRegex.first(youTubePattern, in: url, options: [.caseInsensitive]) else { return nil }
        return RulesRegex.group(m, 1, in: url)
    }

    static func youTubeThumb(_ id: String) -> String { "https://i.ytimg.com/vi/\(id)/hqdefault.jpg" }

    // MARK: Titles

    /// Last part of the path, cleaned and capitalized; the host when the path says nothing; the input when it isn't a URL.
    static func titleFromURL(_ url: String) -> String {
        guard let comps = URLComponents(string: url), let rawHost = comps.host, !rawHost.isEmpty else { return url }
        let host = RulesRegex.replace("^www\\.", in: rawHost.lowercased(), with: "")
        let last = comps.percentEncodedPath.split(separator: "/").last.map(String.init) ?? ""
        var slug = last.removingPercentEncoding ?? last
        slug = RulesRegex.replace("\\.[a-z0-9]+$", in: slug, with: "", options: [.caseInsensitive])
        slug = RulesRegex.replace("[-_+]+", in: slug, with: " ")
        slug = RulesRegex.trim(slug)
        if !slug.isEmpty && !RulesRegex.test("^\\d+$", slug) { return RulesRegex.capitalizeFirst(slug) }
        return host
    }

    /// First line, 90 characters at most.
    static func firstLine(_ text: String) -> String {
        let line = RulesRegex.trim(text.components(separatedBy: "\n").first ?? "")
        if line.count > 90 { return RulesRegex.trim(String(line.prefix(87))) + "\u{2026}" }
        return line
    }

    // MARK: Quotes

    /// A quote: wrapped in quote marks, or a passage ending in an attribution. Author is "" when none.
    static func parseQuote(_ raw: String) -> (text: String, author: String)? {
        let text = RulesRegex.trim(raw)
        if text.isEmpty || text.count > 600 || !findURL(text).isEmpty { return nil }
        let q = "[\(quoteMarks)]"
        let wrappedPattern = "^\(q)([\\s\\S]+?)\(q)[\\s,]*(?:(?:[-\u{2013}\u{2014}~]+|\\n)\\s*(.+))?$"
        if let m = RulesRegex.first(wrappedPattern, in: text) {
            let body = RulesRegex.trim(RulesRegex.group(m, 1, in: text) ?? "")
            let rawAuthor = RulesRegex.group(m, 2, in: text) ?? ""
            let author = cleanAuthor(rawAuthor)
            if !rawAuthor.isEmpty && author.isEmpty { return nil }
            return (body, author)
        }
        let dashedPattern = "^([\\s\\S]{12,}?)(\\s*\\n\\s*|\\s*)([-\u{2013}\u{2014}~]{1,2})\\s*([^\\n]{2,60})$"
        if let m = RulesRegex.first(dashedPattern, in: text) {
            let body = RulesRegex.trim(RulesRegex.group(m, 1, in: text) ?? "")
            let separator = RulesRegex.group(m, 2, in: text) ?? ""
            let dash = RulesRegex.group(m, 3, in: text) ?? ""
            // A plain hyphen after a fragment is usually a to-do ("call Sam - Tuesday"), so it needs a
            // finished sentence; an em dash, en dash or line break is enough on its own.
            let strong = RulesRegex.hasNewline(separator) || dash != "-"
            let sentence = RulesRegex.test("[.!?\u{201D}\"']$", body) && RulesRegex.wordCount(body) >= 4
            let author = cleanAuthor(RulesRegex.group(m, 4, in: text) ?? "")
            if !author.isEmpty && (strong || sentence) { return (stripQuotes(body), author) }
        }
        return nil
    }

    /// A name or short source: capitalized, seven words or fewer, not a day, month or to-do word.
    static func cleanAuthor(_ s: String) -> String {
        let a = RulesRegex.replace("[.;]+$", in: RulesRegex.trim(s), with: "")
        if a.isEmpty { return "" }
        if RulesRegex.wordCount(a) > 7 || !RulesRegex.test("^[A-Z\\u00C0-\\u024F]", a) { return "" }
        if RulesRegex.test(notAuthorsPattern, a, options: [.caseInsensitive]) { return "" }
        return a
    }

    static func stripQuotes(_ s: String) -> String {
        let q = "[\(quoteMarks)]"
        return RulesRegex.trim(RulesRegex.replace("^\(q)+|\(q)+$", in: RulesRegex.trim(s), with: ""))
    }

    // MARK: Files

    /// Kind of a file from its MIME type and name (SPEC 2.2). Text, audio and documents are `file`.
    public static func kind(mime: String?, fileName: String?) -> SaveKind {
        let m = (mime ?? "").lowercased()
        let name = fileName ?? ""
        let ext = name.split(separator: ".", omittingEmptySubsequences: false).last.map { $0.lowercased() } ?? ""
        if m.hasPrefix("image/") || ["heic", "heif", "jpg", "jpeg", "png", "gif", "webp"].contains(ext) { return .photo }
        if m == "application/pdf" || ext == "pdf" { return .pdf }
        if m.hasPrefix("video/") { return .video }
        return .file
    }

    // MARK: Wrapped links

    /// Outlook Safe Links, Google redirects and urldefense links, unwrapped to the real address (up to 3 layers).
    public static func unwrapLink(_ raw: String) -> String {
        var s = RulesRegex.trim(raw)
        for _ in 0..<3 {
            guard let comps = URLComponents(string: s), comps.scheme != nil,
                  let host = comps.host?.lowercased(), !host.isEmpty else { return s }
            var inner: String?
            if host.hasSuffix("safelinks.protection.outlook.com") {
                inner = queryValue(comps, "url")
            } else if RulesRegex.test("^(www\\.)?google\\.[a-z.]+$", host) && comps.path == "/url" {
                inner = queryValue(comps, "q") ?? queryValue(comps, "url")
            } else if host.hasSuffix("urldefense.com") {
                let path = comps.percentEncodedPath
                if let m = RulesRegex.first("__(https?://.+?)__", in: path) { inner = RulesRegex.group(m, 1, in: path) }
            }
            guard let next = inner, !next.isEmpty else { return s }
            s = next
        }
        return s
    }

    static func queryValue(_ comps: URLComponents, _ name: String) -> String? {
        guard let v = comps.queryItems?.first(where: { $0.name == name })?.value, !v.isEmpty else { return nil }
        return v
    }
}

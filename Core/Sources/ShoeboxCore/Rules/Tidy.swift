import Foundation

/// Keeping the lists tidy (SPEC 2.4): a title worth reading, a topic, and the posts from one place kept together.
/// Rules only, on the phone. Nothing here changes what was kept: only how it is shown.
public enum Tidy {
    /// What the rules need from a post.
    public struct Item: Sendable, Equatable {
        public var id: String
        public var title: String
        public var snippet: String
        public var note: String
        public var url: String?
        public var origin: String
        public var emailSubject: String?
        /// The post's kind as stored: link, note, photo, quote, video, file, email.
        public var kind: String

        public init(id: String, title: String, snippet: String = "", note: String = "", url: String? = nil,
                    origin: String = "", emailSubject: String? = nil, kind: String = "link") {
            self.id = id; self.title = title; self.snippet = snippet; self.note = note; self.url = url
            self.origin = origin; self.emailSubject = emailSubject; self.kind = kind
        }

        var host: String? { Tidy.host(url) }
    }

    // MARK: Titles

    /// A title that says nothing: empty, "A photo", a bare link, the site's name, or an id such as "Id1120837655".
    public static func isPlaceholder(_ title: String, url: String?) -> Bool {
        let t = RulesRegex.trim(title)
        if t.isEmpty || looksLikeURL(t) { return true }
        let lower = t.lowercased()
        if ["a photo", "untitled", "photo", "image", "link"].contains(lower) { return true }
        if RulesRegex.test("^id\\d{4,}$", lower) || RulesRegex.test("^\\d+$", lower) { return true }
        if let host = host(url), lower == host { return true }
        return false
    }

    public static func looksLikeURL(_ s: String) -> Bool {
        RulesRegex.test("^(https?://|www\\.)\\S+$", RulesRegex.trim(s), options: [.caseInsensitive])
    }

    /// The title to show. A real title is kept as it is. A placeholder is replaced by the first sentence of what the
    /// post says, then (in lists, where the reason is not shown) your reason, then a plain name for the link.
    public static func title(_ i: Item, useNote: Bool = false) -> String {
        let t = RulesRegex.trim(i.title)
        if !isPlaceholder(t, url: i.url) { return t }
        if let s = firstSentence(i.snippet) { return s }
        let note = RulesRegex.trim(i.note)
        if useNote, !note.isEmpty { return note }
        if let link = i.url ?? (looksLikeURL(t) ? t : nil), let label = linkLabel(link) { return label }
        if i.kind == "photo" { return "A photo" }
        return t.isEmpty ? "Untitled" : t
    }

    /// The first sentence, if it is words and not a link: 2 words at least, 100 characters at most.
    static func firstSentence(_ text: String) -> String? {
        var s = RulesRegex.trim(text.components(separatedBy: .newlines).first ?? "")
        if let r = s.range(of: ". ") { s = String(s[..<r.lowerBound]) }
        s = RulesRegex.trim(s)
        guard !s.isEmpty, !looksLikeURL(s), s.split(separator: " ").count >= 2 else { return nil }
        if s.count > 100 {
            let cut = s.prefix(100)
            s = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        }
        return s
    }

    /// A plain name for a link from a site everyone knows, or "Link from <site>".
    static func linkLabel(_ url: String) -> String? {
        guard let host = host(url) else { return nil }
        let path = (URLComponents(string: url)?.path ?? "").lowercased()
        func on(_ site: String) -> Bool { host == site || host.hasSuffix("." + site) }
        if on("instagram.com") { return path.hasPrefix("/reel") ? "Instagram reel" : path.hasPrefix("/p/") ? "Instagram post" : "Instagram" }
        if on("tiktok.com") { return "TikTok video" }
        if on("youtube.com") || on("youtu.be") { return "YouTube video" }
        if on("x.com") || on("twitter.com") { return "Post on X" }
        if on("facebook.com") { return "Facebook post" }
        if on("apps.apple.com") { return "An app on the App Store" }
        if on("docs.google.com") { return "Google Doc" }
        return "Link from \(host)"
    }

    static func host(_ url: String?) -> String? {
        guard let url, let h = URLComponents(string: url)?.host?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    // MARK: Topics

    /// The topics, in the order they are tried. Something else is always last.
    public enum Topic: String, CaseIterable, Sendable {
        case apps = "Apps"
        case school = "School"
        case food = "Food"
        case travel = "Travel"
        case shopping = "Shopping"
        case work = "Work"
        case watch = "Watch"
        case reading = "Reading"
        case other = "Something else"
    }

    private static let words: [(Topic, String)] = [
        (.school, "school|schools|teachers?|classroom|students?|homework|pta|pto|principal|field trip|picture (re)?take|picture day|retake day|report cards?|conferences?|semester|kindergarten|\\d+(st|nd|rd|th) grade|graders?|early release|parent night|spirit week"),
        (.food, "recipes?|salad|dinner|lunch|breakfast|cook|cooking|bake|baking|soup|chicken|tuna|pasta|restaurant|meal|meals|dessert"),
        (.travel, "flights?|hotels?|airbnb|trip|itinerary|boarding pass|vacation|check-in"),
        (.shopping, "cart|shopping|order|orders|sale|deal|buy|price|watch bands?|ring|necklace|shoes|jacket|gift"),
        (.work, "meeting|agenda|project|scrum|agile|sprint|devops|pipeline|analytics|engineering|career|resume|data science|leadership"),
    ]

    private static let siteTopics: [(Topic, [String])] = [
        (.apps, ["apps.apple.com", "play.google.com"]),
        (.shopping, ["amazon.com", "etsy.com", "target.com", "walmart.com", "ebay.com"]),
        (.work, ["linkedin.com", "github.com"]),
        (.watch, ["youtube.com", "youtu.be", "tiktok.com", "vimeo.com"]),
    ]

    public static func topic(_ i: Item) -> Topic {
        let host = i.host ?? ""
        func on(_ sites: [String]) -> Bool { sites.contains { host == $0 || host.hasSuffix("." + $0) } }
        if on(siteTopics[0].1) { return .apps }
        let text = [title(i, useNote: true), i.snippet, i.note, i.emailSubject ?? ""].joined(separator: " ")
        for (topic, pattern) in words where RulesRegex.test("\\b(\(pattern))\\b", text, options: [.caseInsensitive]) {
            return topic
        }
        for (topic, sites) in siteTopics.dropFirst() where on(sites) { return topic }
        if i.kind == "video" || (host.hasSuffix("instagram.com") && (i.url ?? "").contains("/reel")) { return .watch }
        if ["link", "file", "quote", "email"].contains(i.kind) || i.emailSubject != nil { return .reading }
        return .other
    }

    // MARK: Groups and folds

    /// One row of a list: a post, or several from one place (one email, one page, the same thing kept twice).
    public enum Row: Equatable, Sendable {
        case one(Item)
        case fold(key: String, title: String, items: [Item])

        public var id: String {
            switch self {
            case .one(let i): return i.id
            case .fold(let key, _, _): return "fold:" + key
            }
        }
        public var items: [Item] {
            switch self {
            case .one(let i): return [i]
            case .fold(_, _, let items): return items
            }
        }
    }

    public struct Group: Equatable, Sendable {
        public var topic: Topic
        public var rows: [Row]
        public var count: Int { rows.reduce(0) { $0 + $1.items.count } }
    }

    /// Posts that belong together: the same email, the same page, or the same title.
    public static func foldKey(_ i: Item) -> String {
        if let s = i.emailSubject.map(RulesRegex.trim), !s.isEmpty { return "mail:" + s.lowercased() }
        if let u = i.url, var c = URLComponents(string: u), c.host != nil {
            c.query = nil; c.fragment = nil
            return "url:" + (c.string ?? u).lowercased()
        }
        return "title:" + title(i, useNote: true).lowercased()
    }

    /// Groups posts by topic, largest first and Something else last. Posts from one place sit in one fold, which
    /// takes the topic most of its posts have. The order posts arrive in (newest first) is kept inside each group.
    public static func groups(_ items: [Item]) -> [Group] {
        var keys: [String] = []
        var buckets: [String: [Item]] = [:]
        for i in items {
            let k = foldKey(i)
            if buckets[k] == nil { keys.append(k) }
            buckets[k, default: []].append(i)
        }
        var byTopic: [Topic: [Row]] = [:]
        for k in keys {
            let members = buckets[k] ?? []
            let row: Row = members.count == 1 ? .one(members[0]) : .fold(key: k, title: foldTitle(members), items: members)
            byTopic[majority(members.map { topic($0) }), default: []].append(row)
        }
        let order = Topic.allCases
        return byTopic.map { Group(topic: $0.key, rows: $0.value) }.sorted { a, b in
            if (a.topic == .other) != (b.topic == .other) { return b.topic == .other }
            if a.count != b.count { return a.count > b.count }
            return order.firstIndex(of: a.topic)! < order.firstIndex(of: b.topic)!
        }
    }

    /// Most of a fold's posts decide its topic; Something else only when none has another.
    static func majority(_ topics: [Topic]) -> Topic {
        let named = topics.filter { $0 != .other }
        guard !named.isEmpty else { return .other }
        var counts: [Topic: Int] = [:]
        for t in named { counts[t, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        return named.first { counts[$0] == best } ?? .other
    }

    static func foldTitle(_ items: [Item]) -> String {
        let titles = items.map { title($0, useNote: true) }
        if Set(titles.map { $0.lowercased() }).count == 1 { return titles[0] }
        if let s = items.first?.emailSubject.map(RulesRegex.trim), !s.isEmpty { return s }
        if let origin = items.first.map({ RulesRegex.trim($0.origin) }), !origin.isEmpty { return "From \(origin)" }
        if let host = items.first?.host { return "From \(host)" }
        return titles[0]
    }
}

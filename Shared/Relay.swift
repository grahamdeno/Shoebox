import Foundation
import UIKit

/// Shoebox's relay (the Cloudflare Worker from Shoebox 1). Used for link previews and the email inbox.
/// It answers only requests from Shoebox, which it checks by the Origin header.
enum Relay {
    static let base = URL(string: "https://shoebox-api.tangomike.app")!
    static let origin = "https://inmyshoebox.com"

    static func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, key: String? = nil) -> URLRequest {
        var comps = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 15
        req.setValue(origin, forHTTPHeaderField: "Origin")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { req.setValue(key, forHTTPHeaderField: "x-inbox-key") }
        return req
    }

    struct Preview: Decodable {
        var title: String?
        var description: String?
        var image: String?
        var site: String?
        var text: String?
    }

    /// The page's title, description, best picture and readable text.
    static func preview(_ url: URL) async -> Preview? {
        let req = request("preview", query: [.init(name: "url", value: url.absoluteString), .init(name: "text", value: "1")])
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Preview.self, from: data)
    }

    /// Downloads a picture and shrinks it to 1200 px wide. Small pictures (icons, logos) are refused.
    static func picture(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return thumbnail(data)
    }

    static func thumbnail(_ data: Data, maxWidth: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data), image.size.width >= 300, image.size.height >= 160 else { return nil }
        let scale = min(1, maxWidth / image.size.width)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.8)
    }

    /// Fills in a link save from its page: title, snippet, text and picture. Your own words are never replaced.
    @MainActor
    static func enrich(_ save: Save) async {
        guard let url = save.url, save.enrichedAt == nil, save.enrichTries < 3 else { return }
        save.enrichTries += 1
        guard let p = await preview(url) else { return }
        if let t = p.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           save.title.isEmpty || save.title == save.host || save.title == url.absoluteString {
            save.title = String(t.prefix(140))
        }
        if save.snippet.isEmpty, let d = p.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            save.snippet = String(d.prefix(280))
        }
        if save.body.isEmpty, let text = p.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            save.body = String(text.prefix(20_000))
        }
        if save.origin.isEmpty, let site = p.site, !site.isEmpty { save.origin = site }
        // The page's own picture replaces a stock one found earlier.
        if (save.imageData == nil || save.imageSource == "stock"), let src = p.image ?? save.imageURL, let picURL = URL(string: src, relativeTo: url) {
            save.imageURL = picURL.absoluteString
            if let data = await picture(picURL) {
                save.imageData = data
                save.imageSource = "page"
                save.imageCredit = nil
                save.imageCreditURL = nil
            }
        }
        Capture.adoptDates(save, now: Date())
        save.enrichedAt = Date()
        save.updatedAt = Date()
    }
}

import ShoeboxCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Keep from any app: what was found, why you're keeping it, Keep.
final class ShareViewController: UIViewController {
    private var url: URL?
    private var pageTitle: String?
    private var texts: [String] = []
    private var photos: [Data] = []
    private var comment = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { @MainActor in
            await collect()
            show()
        }
    }

    @MainActor
    private func show() {
        let model = ShareModel(url: url, pageTitle: pageTitle, texts: texts, photos: photos, comment: comment)
        model.onClose = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        let host = UIHostingController(rootView: ShareSheet(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
        ])
        host.didMove(toParent: self)
        model.start()
    }

    // MARK: Reading what was shared

    @MainActor
    private func collect() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            if let c = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { comment = String(c.prefix(140)) }
            pageTitle = pageTitle ?? item.attributedTitle?.string
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), let u = await loadURL(p), !u.isFileURL {
                    url = url ?? u
                } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let d = await loadData(p, type: .image) { photos.append(d) }
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let t = await loadText(p) {
                    texts.append(t)
                }
            }
        }
        // A shared comment that's really the page title isn't a reason.
        if let t = pageTitle, comment == t { comment = "" }
        if let first = texts.first, comment == first { comment = "" }
    }

    private func loadURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { c in _ = p.loadObject(ofClass: URL.self) { u, _ in c.resume(returning: u) } }
    }

    private func loadText(_ p: NSItemProvider) async -> String? {
        await withCheckedContinuation { c in _ = p.loadObject(ofClass: String.self) { s, _ in c.resume(returning: s) } }
    }

    private func loadData(_ p: NSItemProvider, type: UTType) async -> Data? {
        let t = p.registeredContentTypes.first { $0.conforms(to: type) } ?? type
        return await withCheckedContinuation { c in _ = p.loadDataRepresentation(for: t) { d, _ in c.resume(returning: d) } }
    }
}

@MainActor
@Observable
final class ShareModel {
    let url: URL?
    let texts: [String]
    let photos: [Data]
    var title: String
    var site: String
    var picture: UIImage?
    var why: String
    var kept = false
    var keptLabel = ""
    var onClose: () -> Void = {}

    private var preview: Relay.Preview?
    private var pictureData: Data?

    init(url: URL?, pageTitle: String?, texts: [String], photos: [Data], comment: String) {
        self.url = url
        self.texts = texts
        self.photos = photos
        self.why = comment
        self.site = url?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        if let pageTitle, !pageTitle.isEmpty { title = pageTitle }
        else if let first = texts.first { title = String(first.prefix(120)) }
        else if !photos.isEmpty { title = photos.count == 1 ? "A photo" : "\(photos.count) photos" }
        else { title = url?.absoluteString ?? "" }
        if let first = photos.first { picture = UIImage(data: first) }
    }

    /// Reads the page while you type your reason.
    func start() {
        guard let url else { return }
        Task {
            guard let p = await Relay.preview(url) else { return }
            preview = p
            if let t = p.title, !t.isEmpty { title = t }
            if let s = p.site, !s.isEmpty { site = s }
            if let src = p.image, let u = URL(string: src, relativeTo: url), let d = await Relay.picture(u) {
                pictureData = d
                picture = UIImage(data: d)
            }
        }
    }

    func keep() {
        guard !kept, let container = try? Store.make() else { onClose(); return }
        let context = container.mainContext
        let note = why.trimmingCharacters(in: .whitespacesAndNewlines)
        var saves: [Save] = []
        if let url {
            let s = Capture.save(fromURL: url, title: title, note: note, origin: "")
            if let p = preview {
                if let d = p.description, !d.isEmpty { s.snippet = String(d.prefix(280)) }
                if let t = p.text, !t.isEmpty { s.body = String(t.prefix(20_000)) }
                if let i = p.image { s.imageURL = i }
                if let site = p.site, !site.isEmpty { s.origin = site }
            }
            if let pictureData { s.imageData = pictureData; s.enrichedAt = Date() }
            if pictureData != nil || preview != nil { s.enrichedAt = Date() }
            saves.append(s)
        } else if !photos.isEmpty {
            saves = photos.map { Capture.save(photo: $0, note: note, origin: "your photos") }
        } else if !texts.isEmpty {
            saves = Capture.saves(fromText: texts.joined(separator: "\n"), note: note, origin: "a share")
        }
        var added = 0
        for s in saves where !Capture.isDuplicate(s, in: context) {
            context.insert(s)
            added += 1
        }
        try? context.save()
        let back = saves.first?.returnDate.map { LaterPlanner().label(for: $0, now: Date()).lowercased() } ?? "tomorrow"
        keptLabel = added == 0 ? "Already in your Shoebox." : "Kept. It comes back \(back)."
        withAnimation(.snappy) { kept = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            onClose()
        }
    }
}

struct ShareSheet: View {
    @Bindable var model: ShareModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                if model.kept {
                    Text(model.keptLabel)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                } else {
                    Text("Keep it")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    found
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why are you keeping it? (optional)").font(.system(size: 13)).foregroundStyle(Theme.quiet)
                        TextField("Before the trip", text: $model.why, axis: .vertical)
                            .font(.system(size: 17))
                            .lineLimit(1...3)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { model.keep() }
                            .padding(14)
                            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                    }
                    Text("Your why decides when it comes back. Say nothing and it comes back tomorrow.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.quiet)
                    HStack {
                        Button("Cancel", action: model.onClose)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.quiet)
                            .frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .leading)
                        Spacer()
                        LidButton(title: "Keep", action: model.keep)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(Theme.sheet)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetRadius, topTrailingRadius: Metrics.sheetRadius))
        }
        .onAppear { focused = true }
    }

    private var found: some View {
        HStack(alignment: .top, spacing: 12) {
            if let picture = model.picture {
                Image(uiImage: picture)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !model.site.isEmpty {
                    Text(model.site).font(.system(size: 14)).foregroundStyle(Theme.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

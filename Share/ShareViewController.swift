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
        let host = UIHostingController(rootView: ShareSheet(model: model).tint(Theme.accent))
        host.view.backgroundColor = .clear
        switch Prefs.appearance {
        case 1: host.overrideUserInterfaceStyle = .light
        case 2: host.overrideUserInterfaceStyle = .dark
        default: break
        }
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
                    // One at a time, shrunk as they are read from the file the system hands over.
                    if let d = await loadPhoto(p) { photos.append(d) }
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

    /// A shared photo as a small JPEG (2,400 pixels at most). The system hands over a file, not the bytes, and the
    /// file only exists inside this callback, so it is shrunk there. A 48 megapixel photo never sits in memory whole.
    private func loadPhoto(_ p: NSItemProvider) async -> Data? {
        let t = p.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
        let fromFile: Data? = await withCheckedContinuation { c in
            _ = p.loadFileRepresentation(forTypeIdentifier: t.identifier) { url, _ in
                c.resume(returning: url.flatMap { ImageDownsample.jpeg(fromFile: $0) })
            }
        }
        if let fromFile { return fromFile }
        // Some apps hand over only the bytes. They are shrunk straight from the bytes, so the photo is still never
        // decoded whole, and a photo is never lost because it did not come as a file.
        return await withCheckedContinuation { c in
            _ = p.loadDataRepresentation(for: t) { d, _ in
                c.resume(returning: d.flatMap { ImageDownsample.jpeg(from: $0, maxWidth: 2400, quality: 0.85) ?? $0 })
            }
        }
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
    /// Set when the save could not be made. The sheet stays open with what was typed, so nothing is lost.
    var problem: String?
    var onClose: () -> Void = {}
    /// When it starts coming back. Automatic: your words decide.
    var choice: ReturnChoice = .auto

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

    static let couldNotKeep = "Couldn't keep that. Open Shoebox once, then try again."

    func keep() {
        guard !kept else { return }
        let container: ModelContainer
        do { container = try Store.make() } catch {
            problem = ShareModel.couldNotKeep
            return
        }
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
            if let pictureData { s.imageData = pictureData; s.enrichedAt = Clock.now }
            if pictureData != nil || preview != nil { s.enrichedAt = Clock.now }
            saves.append(s)
        } else if !photos.isEmpty {
            saves = photos.map { Capture.save(photo: $0, note: note, origin: "your photos") }
        } else if !texts.isEmpty {
            saves = Capture.saves(fromText: texts.joined(separator: "\n"), note: note, origin: "a share")
        }
        choice.apply(to: saves, now: Clock.now)
        var added = 0
        for s in saves where !Capture.isDuplicate(s, in: context) {
            context.insert(s)
            added += 1
        }
        do { try context.save() } catch {
            context.rollback()
            problem = ShareModel.couldNotKeep
            return
        }
        problem = nil
        let back = saves.first?.returnDate.map { LaterPlanner().label(for: $0, now: Clock.now).lowercased() } ?? "tomorrow"
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
    @State private var showReturn = false

    var body: some View {
        Group {
            if model.kept { keptView } else { surface }
        }
        // The host already ends above the keyboard.
        .ignoresSafeArea(.keyboard)
        .onAppear { focused = true }
    }

    private var keptView: some View {
        ZStack {
            SurfaceGround(picture: model.picture).ignoresSafeArea()
            Text(model.keptLabel)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.onPhoto)
                .multilineTextAlignment(.center)
                .padding(24)
        }
        .environment(\.colorScheme, .dark)
    }

    private var event: Date? { DateReader.read(model.title, created: Clock.now)?.event }

    /// The same surface as Keep something: what was found is the post, your reason goes under it.
    private var surface: some View {
        WritingSurface(onLeading: model.onClose, onTrailing: model.keep) {
            SurfaceGround(picture: model.picture)
        } panel: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.onPhoto)
                    .lineLimit(4)
                if !model.site.isEmpty {
                    Text(model.site)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onPhoto.opacity(0.6))
                        .lineLimit(1)
                }
            }
            SurfaceLine(label: "Why") {
                TextField("", text: $model.why,
                          prompt: Text("Optional. Before the trip").foregroundStyle(Theme.onPhoto.opacity(0.4)),
                          axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { model.keep() }
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onPhoto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button { focused = false; showReturn = true } label: {
                    Text(ReturnLine.text(model.choice, event: event, why: model.why))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onPhoto.opacity(0.85))
                        .frame(minHeight: Metrics.touchMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showReturn) {
            ReturnSheet(choice: $model.choice, autoLine: ReturnLine.text(.auto, event: event, why: model.why))
                .presentationDetents([.height(420)])
        }
    }
}

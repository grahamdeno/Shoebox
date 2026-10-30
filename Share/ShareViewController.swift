import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ShoeboxCore

/// Save from any app: what Shoebox found, your reason typed or spoken, Keep it (SPEC 2.3).
final class ShareViewController: UIViewController {
    private var drafts: [Detection.Draft] = []
    private var files: [(data: Data, mime: String, name: String?)] = []
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
        let keeper = Keeper(context: StoreBox.container.mainContext)
        let events = CalendarReader.upcoming()
        let first = drafts.first ?? Detection.Draft(kind: files.isEmpty ? .note : Detection.kind(mime: files[0].mime, fileName: files[0].name),
                                                    title: files.first?.name ?? "", text: nil, url: nil, author: nil, videoId: nil, imageURL: nil)
        var saved: [Save] = []
        let found = Self.found(first, count: max(drafts.count, files.count))
        let root = CaptureView(
            found: found,
            title: first.title,
            initialReason: comment,
            onSave: { reason, spoken in
                let source: ReasonSource = spoken ? .spoken : (reason == self.comment && !reason.isEmpty ? .shareComment : .typed)
                var last: PlanOutcome?
                if self.drafts.isEmpty {
                    let (s, o) = keeper.keep(first, reason: reason, reasonSource: source, source: .share, files: self.files, events: events)
                    saved.append(s); last = o
                } else {
                    for (i, d) in self.drafts.enumerated() {
                        let (s, o) = keeper.keep(d, reason: reason, reasonSource: source, source: .share,
                                                 files: i == 0 ? self.files : [], events: events)
                        saved.append(s); last = o
                    }
                }
                Task { await Engine.schedule(keeper); WidgetsBridge.reload() }
                return last ?? .moment(PlannedMoment(start: .now, end: .now, surface: .issue, place: .any, ruleId: "R20", confidence: .guess,
                                                     explanation: "Kept", laterLabel: "Tomorrow", anchorEventId: nil))
            },
            onChange: { choice in
                var p: PlannedMoment?
                for s in saved { p = keeper.later(s, choice, events: events, surface: "share") }
                Task { await Engine.schedule(keeper) }
                return p ?? ReturnPlanner.later(choice, input: PlanInput(reason: "", kind: first.kind, minutes: nil, intent: nil, title: "",
                                                                         now: .now, events: [], plannedPerDay: [:], hints: nil))
            },
            onPick: { date in
                for s in saved { keeper.later(s, at: date, surface: "share") }
                Task { await Engine.schedule(keeper) }
            },
            onClose: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        .themed()

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.sizingOptions = .preferredContentSize
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            host.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
        ])
        host.view.layer.cornerRadius = Metric.radiusMd
        host.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        host.view.clipsToBounds = true
        host.didMove(toParent: self)
    }

    static func found(_ d: Detection.Draft, count: Int) -> String {
        let what: String = switch d.kind {
        case .link: "Link"
        case .video: "Video"
        case .photo: count > 1 ? "\(count) photos" : "Photo"
        case .pdf: "PDF"
        case .quote: "Quote"
        case .note: "Note"
        case .file: "File"
        }
        let host = d.url.flatMap(URL.init(string:))?.host()?.replacingOccurrences(of: "www.", with: "")
        if case .link = d.kind, count > 1 { return "\(count) links" }
        return [what, host].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Reading what was shared

    @MainActor
    private func collect() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        var texts: [String] = []
        var url: URL?
        var pageTitle: String?
        for item in items {
            if let c = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { comment = SpokenReason.clip(c) }
            pageTitle = pageTitle ?? item.attributedTitle?.string
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), let u = await loadURL(p), !u.isFileURL {
                    url = url ?? u
                } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) || p.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                            || p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || p.hasItemConformingToTypeIdentifier(UTType.data.identifier) && !p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let f = await loadFile(p) { files.append(f) }
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let t = await loadText(p) {
                    texts.append(t)
                }
            }
        }
        // A shared comment that's really the page title isn't a reason.
        if let t = pageTitle, comment == t { comment = "" }
        if let url {
            drafts = [Detection.draft(fromURL: url, title: pageTitle ?? texts.first)]
        } else if !texts.isEmpty {
            drafts = Detection.drafts(fromText: texts.joined(separator: "\n"))
        }
    }

    private func loadURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { c in
            _ = p.loadObject(ofClass: URL.self) { u, _ in c.resume(returning: u) }
        }
    }

    private func loadText(_ p: NSItemProvider) async -> String? {
        await withCheckedContinuation { c in
            _ = p.loadObject(ofClass: String.self) { s, _ in c.resume(returning: s) }
        }
    }

    private func loadFile(_ p: NSItemProvider) async -> (data: Data, mime: String, name: String?)? {
        let type = p.registeredContentTypes.first { $0.conforms(to: .image) || $0.conforms(to: .pdf) || $0.conforms(to: .movie) } ?? p.registeredContentTypes.first ?? .data
        let name = p.suggestedName.map { n in n.contains(".") ? n : n + "." + (type.preferredFilenameExtension ?? "bin") }
        let data: Data? = await withCheckedContinuation { c in
            _ = p.loadDataRepresentation(for: type) { d, _ in c.resume(returning: d) }
        }
        guard let data else { return nil }
        return (data, type.preferredMIMEType ?? "application/octet-stream", name)
    }
}

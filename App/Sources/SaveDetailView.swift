import SwiftUI
import SafariServices
import SwiftData
import ShoeboxCore

/// One save: your reason largest, the thing itself, and the three verdicts (or Bring it back).
struct SaveDetailView: View {
    let id: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft = ""
    @State private var laterOpen = false
    @State private var picking = false
    @State private var picked = Date.now.addingTimeInterval(3600)
    @State private var confirmDelete = false
    @State private var save: Save?
    @State private var browsing: URL?

    private var keeper: Keeper { Keeper(context: context) }

    var body: some View {
        Group {
            if let save, save.deletedAt == nil { content(save) } else { Text("This save was deleted.").type(.body).foregroundStyle(roles.quiet) }
        }
        .background(roles.surface)
        .onAppear {
            save = keeper.save(id: id)
            if let save { keeper.opened(save, surface: "app") }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme?.hasPrefix("http") == true else { return .systemAction }
            browsing = url
            return .handled
        })
        .sheet(item: $browsing) { SafariView(url: $0).ignoresSafeArea() }
        .confirmationDialog("Delete this save?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let save { keeper.delete(save); let sid = save.id; Task { await LiveMoments.end(saveId: sid) } }
                Task { await model.refresh() }
                dismiss()
            }
        } message: { Text("It's removed from your iPhone for good. Drop keeps it under Let go instead.") }
    }

    @ViewBuilder
    private func content(_ s: Save) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.space4) {
                HStack(spacing: Metric.space2) {
                    AppMark()
                    Text(meta(s)).type(.meta).foregroundStyle(roles.quiet).lineLimit(1)
                }
                if editing {
                    TextField("", text: $draft, prompt: Text("Why are you keeping it?"), axis: .vertical)
                        .type(.reasonLg).lineLimit(1...5)
                        .padding(Metric.space3)
                        .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.focus, lineWidth: 2))
                    HStack {
                        Button("Save the reason") {
                            keeper.editReason(s, to: draft, events: CalendarReader.upcoming()); editing = false
                            Task { await model.refresh() }
                        }.buttonStyle(LineButtonStyle())
                        Button("Cancel") { editing = false }.buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button { draft = s.reason; editing = true } label: {
                        Text(s.reason.isEmpty ? "Add why you kept it" : s.reason)
                            .type(.reasonXl)
                            .foregroundStyle(s.reason.isEmpty ? roles.quiet : roles.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit your reason")
                }
                if let m = keeper.nextMoment(for: s), s.status == .planned {
                    Text(m.explanation).type(.body).foregroundStyle(roles.quiet)
                } else {
                    Text(statusLine(s)).type(.body).foregroundStyle(roles.quiet)
                }
                if let pic = keeper.picture(for: s), let img = UIImage(contentsOfFile: pic.path()) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Metric.radiusPicture))
                        .accessibilityLabel(s.alt.isEmpty ? "Picture" : s.alt)
                }
                thing(s)
                verdicts(s)
                if !s.thoughts.isEmpty {
                    VStack(alignment: .leading, spacing: Metric.space2) {
                        Text("Your notes").type(.meta).foregroundStyle(roles.quiet)
                        ForEach(Array(s.thoughts.enumerated()), id: \.offset) { _, t in Text(t.text).type(.body) }
                    }
                }
                Hairline().padding(.top, Metric.space4)
                Button("Delete") { confirmDelete = true }.buttonStyle(QuietButtonStyle())
            }
            .padding(Metric.space5)
        }
        .sheet(isPresented: $picking) {
            VStack(spacing: Metric.space4) {
                DatePicker("", selection: $picked, in: Date.now..., displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical).labelsHidden()
                Button("Bring it back then") {
                    keeper.later(s, at: picked, surface: "app"); picking = false; laterOpen = false
                    Task { await model.refresh() }
                }.buttonStyle(ActButtonStyle())
            }
            .padding(Metric.space5).themed(model.roles).presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func thing(_ s: Save) -> some View {
        VStack(alignment: .leading, spacing: Metric.space2) {
            if !s.reason.isEmpty && s.title != s.reason { Text(s.title).type(.title) }
            if let author = s.author, !author.isEmpty { Text(author).type(.label).foregroundStyle(roles.quiet) }
            if let text = s.text, !text.isEmpty { LinkedText(text: text) }
            if !s.summary.isEmpty { LinkedText(text: s.summary, quiet: true) }
            ForEach(s.points, id: \.self) { p in Text("· " + p).type(.body) }
            if let u = s.url.flatMap(URL.init(string:)) {
                Button { keeper.opened(s, surface: "app"); browsing = u } label: {
                    HStack { Text("Open \(s.host ?? "link")").type(.button); Image(systemName: "arrow.up.right") }
                }
                .buttonStyle(LineButtonStyle())
            } else if let file = keeper.attachments(for: s).first(where: { $0.role == .original && !$0.mime.hasPrefix("image/") }) {
                ShareLink(item: file.fileURL) { Text("Open the file").type(.button) }.buttonStyle(LineButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func verdicts(_ s: Save) -> some View {
        let events = CalendarReader.upcoming()
        switch s.status {
        case .planned, .unplanned:
            VStack(spacing: Metric.space2) {
                HStack(spacing: Metric.space2) {
                    Button(Engine.doneWord(s)) { act { keeper.done(s, surface: "app") ; return "Done. It won't come back." } }
                        .buttonStyle(ActButtonStyle())
                    Button(keeper.nextMoment(for: s)?.laterLabel ?? "Later") { laterOpen.toggle() }
                        .buttonStyle(LineButtonStyle())
                    Button("Drop") { act { keeper.drop(s, surface: "app"); return "Dropped. It's under Let go." } }
                        .buttonStyle(QuietButtonStyle())
                }
                if laterOpen {
                    if QuietRule.laterNeedsQuestion(laters: s.laters + 1) {
                        Text("Keep it, or let it go quiet?").type(.label).foregroundStyle(roles.quiet)
                        Button("Let it go quiet") {
                            act { keeper.pass(s, events: events, surface: "app"); keeper.pass(s, events: events, surface: "app"); return "It's gone quiet. Find it any time." }
                        }.buttonStyle(LineButtonStyle())
                    }
                    ForEach([LaterChoice.tonight, .tomorrowMorning, .thisWeekend, .nextWeek, .youChoose], id: \.self) { c in
                        Button(CaptureView.label(c)) {
                            let p = keeper.later(s, c, events: events, surface: "app"); laterOpen = false
                            model.toast = .init(text: p.explanation, undo: nil)
                            Task { await model.refresh() }
                        }.buttonStyle(LineButtonStyle())
                    }
                    Button("Pick a time") { picking = true }.buttonStyle(LineButtonStyle())
                }
            }
        case .quiet, .done, .dropped:
            VStack(alignment: .leading, spacing: Metric.space2) {
                Button(s.status == .quiet ? "Bring it back" : "Restore") { laterOpen.toggle() }.buttonStyle(ActButtonStyle())
                if laterOpen {
                    ForEach([LaterChoice.tonight, .tomorrowMorning, .thisWeekend, .nextWeek, .youChoose], id: \.self) { c in
                        Button(CaptureView.label(c)) {
                            keeper.bringBack(s, c, events: events); laterOpen = false
                            Task { await model.refresh() }
                        }.buttonStyle(LineButtonStyle())
                    }
                }
            }
        }
    }

    private func act(_ change: () -> String) {
        let text = change()
        model.toast = .init(text: text, undo: id)
        let sid = id
        Task { await LiveMoments.end(saveId: sid); await model.refresh() }
        dismiss()
    }

    private func meta(_ s: Save) -> String {
        var parts = [s.isSchool ? "School" : s.kind.rawValue.capitalized]
        if let h = s.host { parts.append(h) }
        parts.append("Kept " + s.createdAt.formatted(.dateTime.month(.abbreviated).day()))
        return parts.joined(separator: " · ")
    }

    private func statusLine(_ s: Save) -> String {
        switch s.status {
        case .quiet: "Quiet. Kept, and not offered unless you ask."
        case .done: "Done" + (s.doneAt.map { " " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "") + "."
        case .dropped: "Let go. Kept here, and never deleted on its own."
        case .unplanned: "Finding a good time."
        case .planned: ""
        }
    }
}


/// Text whose web addresses are tappable, unwrapped from Safe Links and redirects (SPEC 7.6).
struct LinkedText: View {
    let text: String
    var quiet = false
    @Environment(\.roles) private var roles

    var body: some View {
        Text(attributed).type(.body).foregroundStyle(quiet ? roles.quiet : roles.text).tint(roles.actText).textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text), let ar = Range(r, in: a), let url = m.url else { continue }
            let clean = URL(string: Detection.unwrapLink(url.absoluteString)) ?? url
            a[ar].link = clean
            a[ar].underlineStyle = .single
        }
        return a
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Links open inside Shoebox, with Safari one tap away.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

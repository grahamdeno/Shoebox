import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Keep something by hand. Most saves come from the share sheet or email.
struct AddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var why = ""
    @State private var error = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var pickedFile: PickedFile?
    @State private var showFiles = false
    @State private var showCamera = false
    /// The day it should start coming back on Today. Until then it waits in the Shoebox, where it can always be found.
    @State private var startDate: Date?
    @FocusState private var focus: Field?

    enum Field { case text, why }

    var body: some View {
        // Laid out like Scales: the words for leaving and keeping sit at the top, so nothing
        // has to rise with the keyboard, and one swipe down closes it.
        VStack(alignment: .leading, spacing: 0) {
            FormTopBar(onLeading: { dismiss() }, trailing: "Keep",
                       trailingEnabled: canKeep, onTrailing: keep)
                .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
            Text("Keep something")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.formInk)
                .padding(.top, 28)

            LineField(label: "Link or note") {
                if let photoData, let img = UIImage(data: photoData) {
                    HStack(spacing: 12) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("A photo")
                        Spacer()
                        Button("Remove") { self.photoData = nil; photo = nil }
                            .font(.system(size: 15)).foregroundStyle(Theme.formQuiet)
                            .frame(minHeight: Metrics.touchMin)
                    }
                } else if let pickedFile {
                    HStack(spacing: 12) {
                        Text(pickedFile.name).lineLimit(2)
                        Spacer()
                        Button("Remove") { self.pickedFile = nil }
                            .font(.system(size: 15)).foregroundStyle(Theme.formQuiet)
                            .frame(minHeight: Metrics.touchMin)
                    }
                } else {
                    TextField("", text: $text, prompt: formPrompt("Paste a link or write a note"), axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focus, equals: .text)
                        .onChange(of: text) { _, _ in error = "" }
                }
            }
            .padding(.top, 36)

            // Right under the field they stand in for, so they sit above the keyboard.
            if photoData == nil && pickedFile == nil {
                HStack(spacing: 20) {
                    Text("Or add").font(.system(size: 15)).foregroundStyle(Theme.formQuiet)
                    PhotosPicker(selection: $photo, matching: .images) { addWord("Photos") }
                    Button { focus = nil; showFiles = true } label: { addWord("Files") }
                    Button { focus = nil; showCamera = true } label: { addWord("Camera") }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }

            LineField(label: "Why are you keeping it?") {
                TextField("", text: $why, prompt: formPrompt("Optional. Before the trip"))
                    .focused($focus, equals: .why)
                    .submitLabel(.done)
                    .onSubmit { if canKeep { keep() } }
            }
            .padding(.top, 28)

            if !error.isEmpty {
                Text(error).font(.system(size: 14)).foregroundStyle(Theme.noteInk)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 16)
            }

            LineField(label: "Start showing it on") {
                if let day = startDate {
                    HStack {
                        DatePicker("", selection: Binding(get: { day }, set: { startDate = $0 }),
                                   in: Self.tomorrow..., displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Theme.accent)
                        Spacer()
                        Button("Clear") { startDate = nil }
                            .font(.system(size: 15)).foregroundStyle(Theme.formQuiet)
                            .frame(minHeight: Metrics.touchMin)
                    }
                } else {
                    Button("Pick a day") { startDate = Self.tomorrow }
                        .font(.system(size: 16, weight: .semibold))
                        .underline()
                        .foregroundStyle(Theme.formInk)
                        .frame(minHeight: Metrics.touchMin)
                }
            }
            .padding(.top, 28)

            Text(startDate == nil
                 ? "Your why decides when it comes back. Say nothing and it comes back tomorrow."
                 : "It waits in your Shoebox until then. You can find it there any time.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.formQuiet)
                .lineSpacing(2)
                .padding(.top, 14)

                    Color.clear.frame(height: 40)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The scroll stops at the keyboard, so everything below can still be reached. Nothing rides it:
        // Cancel and Keep are at the top.
        .background(Theme.formGround.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.formGround)
        .onAppear { focus = .text }
        .onChange(of: photo) { _, item in
            Task { photoData = try? await item?.loadTransferable(type: Data.self) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .rtf, .data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                let (file, problem) = await FileKeeper.read(url)
                if let file { pickedFile = file; error = "" } else if let problem { error = problem }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraSheet { data in photoData = data }
        }
    }

    private static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private func addWord(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .underline()
            .foregroundStyle(Theme.formInk)
            .frame(minHeight: Metrics.touchMin)
            .contentShape(Rectangle())
    }

    private var canKeep: Bool {
        photoData != nil || pickedFile != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func keep() {
        let note = why.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        var saves: [Save] = []
        if let photoData {
            saves = [Capture.save(photo: photoData, note: note, origin: "your photos", now: now)]
        } else if let pickedFile {
            saves = [FileKeeper.save(pickedFile, note: note, now: now)]
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                error = "Add a link or a note first."
                return
            }
            saves = Capture.saves(fromText: trimmed, note: note, origin: "", now: now)
            for s in saves where s.kind == .note || s.kind == .quote { s.origin = "a note" }
        }
        // A start day you chose wins: it waits in the Shoebox, out of Today, until the morning of that day.
        if let day = startDate, let start = Calendar.current.date(byAdding: .hour, value: 8, to: Calendar.current.startOfDay(for: day)), start > now {
            for s in saves {
                s.status = .away; s.returnDate = start; s.seenOn = nil
                // A date read from the words that falls before the day you chose would retire the post
                // before it ever shows. The day you chose is the one that counts.
                if let event = s.eventDate, event < start {
                    s.eventDate = nil; s.eventHasTime = false; s.otherDatesRaw = ""
                }
            }
        }
        var added: [Save] = []
        for s in saves where !Capture.isDuplicate(s, in: context) {
            context.insert(s)
            added.append(s)
        }
        if added.isEmpty && !saves.isEmpty {
            error = "That's already in your Shoebox."
            return
        }
        try? context.save()
        for s in added where s.url != nil {
            Task { await Relay.enrich(s); try? context.save() }
        }
        dismiss()
    }
}

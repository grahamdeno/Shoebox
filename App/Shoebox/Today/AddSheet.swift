import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Keep something by hand. Most saves come from the share sheet or email.
/// You write on the post you are making: its photo is the ground, the words and the why sit on one glass
/// panel, and the bottom row holds Add and when it comes back. SPEC 2.5.
struct AddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var why = ""
    @State private var error = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var pickedFile: PickedFile?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var showReturn = false
    @State private var choice: ReturnChoice = .auto
    @State private var groundID = UUID()
    /// What the phone read from the photo. Shown lighter until you change it.
    @State private var suggestedWords: String?
    @State private var suggestedWhy: String?
    @State private var reading = false
    @State private var readTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        WritingSurface(canKeep: canKeep, onLeading: { dismiss() }, onTrailing: keep) {
            PostPhoto(id: groundID, data: photoData, topClear: 110, bottomClear: 330)
        } panel: {
            if let note = readNote {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.nectarine)
            }

            if let pickedFile {
                Text(pickedFile.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.onPhoto)
                    .lineLimit(2)
            } else {
                TextField("", text: $text,
                          prompt: Text("Paste a link or write a note").foregroundStyle(Theme.onPhoto.opacity(0.45)),
                          axis: .vertical)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.onPhoto.opacity(wordsDim ? 0.68 : 1))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onChange(of: text) { _, _ in error = "" }
            }

            if hasSomething {
                SurfaceLine(label: "Why") {
                    TextField("", text: $why,
                              prompt: Text("Optional. Before the trip").foregroundStyle(Theme.onPhoto.opacity(0.4)))
                        .opacity(whyDim ? 0.72 : 1)
                        .submitLabel(.done)
                        .onSubmit { if canKeep { keep() } }
                }
            }

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.noteInk)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                leftWord
                Spacer()
                Button { focused = false; showReturn = true } label: {
                    Text(returnText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onPhoto.opacity(0.85))
                        .frame(minHeight: Metrics.touchMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.plumNight)
        .onAppear { focused = true }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                take(photo: data)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .rtf, .data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                let (file, problem) = await FileKeeper.read(url)
                if let file { removePhoto(); pickedFile = file; error = "" } else if let problem { error = problem }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCamera { data in take(photo: data) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReturn) {
            ReturnSheet(choice: $choice, autoLine: ReturnLine.text(.auto, event: event, why: why))
                .presentationDetents([.height(420)])
        }
    }

    // MARK: The bottom row

    @ViewBuilder private var leftWord: some View {
        if photoData != nil {
            Button { removePhoto() } label: { SurfaceWord(text: "Remove photo") }.buttonStyle(.plain)
        } else if pickedFile != nil {
            Button { pickedFile = nil } label: { SurfaceWord(text: "Remove file") }.buttonStyle(.plain)
        } else {
            Menu {
                Button("Photo Library") { focused = false; showPhotos = true }
                if SystemCamera.isAvailable {
                    Button("Take Photo") { focused = false; showCamera = true }
                }
                Button("Choose File") { focused = false; showFiles = true }
            } label: {
                SurfaceWord(text: "Add")
            }
        }
    }

    private var returnText: String {
        ReturnLine.text(choice, event: event, why: why)
    }

    /// The date the words are about, so the line can say when it comes back.
    private var event: Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return DateReader.read(t, created: Date())?.event
    }

    // MARK: Suggestions from a photo

    private var wordsDim: Bool { suggestedWords != nil && text == suggestedWords }
    private var whyDim: Bool { suggestedWhy != nil && why == suggestedWhy }

    private var readNote: String? {
        if reading { return "Reading the photo…" }
        if wordsDim || whyDim { return "Read from the photo. Tap to change." }
        return nil
    }

    private var hasSomething: Bool {
        photoData != nil || pickedFile != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func take(photo data: Data) {
        pickedFile = nil
        photoData = data
        groundID = UUID()
        error = ""
        read(data)
    }

    private func removePhoto() {
        readTask?.cancel()
        reading = false
        if let s = suggestedWords, text == s { text = "" }
        if let s = suggestedWhy, why == s { why = "" }
        suggestedWords = nil
        suggestedWhy = nil
        photoData = nil
        photo = nil
        groundID = UUID()
    }

    /// Reads the photo on the phone and fills what is still empty. Anything you have typed is left alone.
    private func read(_ data: Data) {
        readTask?.cancel()
        if let s = suggestedWords, text == s { text = "" }
        if let s = suggestedWhy, why == s { why = "" }
        suggestedWords = nil
        suggestedWhy = nil
        reading = true
        readTask = Task { @MainActor in
            let found = await PhotoRead.recognizedText(in: data)
            let gist = await PhotoRead.gist(from: found)
            guard !Task.isCancelled else { return }
            reading = false
            guard let gist else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = gist.words
                suggestedWords = gist.words
            }
            if why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !gist.why.isEmpty {
                why = gist.why
                suggestedWhy = gist.why
            }
        }
    }

    // MARK: Keeping

    private var canKeep: Bool {
        photoData != nil || pickedFile != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func keep() {
        let note = why.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        var saves: [Save] = []
        if let photoData {
            let s = Capture.save(photo: photoData, note: note, origin: "your photos", now: now)
            // Words over a photo (read from it or yours) are its title and details, and are read for a date.
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty {
                let parts = words.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                s.title = String((parts.first ?? "").prefix(90))
                if parts.count > 1 {
                    s.body = String(parts[1])
                    s.snippet = String(parts[1].prefix(200)).replacingOccurrences(of: "\n", with: " ")
                }
                Capture.place(s, note: note, now: now)
            }
            saves = [s]
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
        choice.apply(to: saves, now: now)
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

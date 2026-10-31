import PhotosUI
import SwiftData
import SwiftUI

/// Keep something by hand. Most saves come from the share sheet or email.
struct AddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var why = ""
    @State private var error = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @FocusState private var focus: Field?

    enum Field { case text, why }

    var body: some View {
        // Laid out like Scales: the words for leaving and keeping sit at the top, so nothing
        // has to rise with the keyboard, and one swipe down closes it.
        VStack(alignment: .leading, spacing: 0) {
            FormTopBar(onLeading: { dismiss() }, trailing: "Keep",
                       trailingEnabled: canKeep, onTrailing: keep)
                .padding(.top, 14)

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
                } else {
                    TextField("", text: $text, prompt: formPrompt("Paste a link or write a note"), axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focus, equals: .text)
                        .onChange(of: text) { _, _ in error = "" }
                }
            }
            .padding(.top, 36)

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

            Text("Your why decides when it comes back. Say nothing and it comes back tomorrow.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.formQuiet)
                .lineSpacing(2)
                .padding(.top, 20)

            if photoData == nil {
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Keep a photo instead")
                        .font(.system(size: 16, weight: .semibold))
                        .underline()
                        .foregroundStyle(Theme.formInk)
                        .frame(minHeight: Metrics.touchMin)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.formGround.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .presentationDetents([.large])
        .presentationBackground(Theme.formGround)
        .onAppear { focus = .text }
        .onChange(of: photo) { _, item in
            Task { photoData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    private var canKeep: Bool {
        photoData != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func keep() {
        let note = why.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        var saves: [Save] = []
        if let photoData {
            saves = [Capture.save(photo: photoData, note: note, origin: "your photos", now: now)]
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                error = "Add a link or a note first."
                return
            }
            saves = Capture.saves(fromText: trimmed, note: note, origin: "", now: now)
            for s in saves where s.kind == .note || s.kind == .quote { s.origin = "a note" }
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

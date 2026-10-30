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
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep something")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 26)

            VStack(alignment: .leading, spacing: 6) {
                Text("Link or note").font(.system(size: 13)).foregroundStyle(Theme.quiet)
                if let photoData, let img = UIImage(data: photoData) {
                    HStack(spacing: 12) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("A photo").font(.system(size: 17)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("Remove") { self.photoData = nil; photo = nil }
                            .font(.system(size: 15)).foregroundStyle(Theme.quiet)
                            .frame(minHeight: Metrics.touchMin)
                    }
                } else {
                    TextField("Paste a link or write a note", text: $text, axis: .vertical)
                        .font(.system(size: 17))
                        .lineLimit(1...5)
                        .focused($focus, equals: .text)
                        .padding(14)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                        .onChange(of: text) { _, _ in error = "" }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Why are you keeping it? (optional)").font(.system(size: 13)).foregroundStyle(Theme.quiet)
                TextField("Before the trip", text: $why)
                    .font(.system(size: 17))
                    .focused($focus, equals: .why)
                    .submitLabel(.done)
                    .padding(14)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
            }

            if !error.isEmpty {
                Text(error).font(.system(size: 14)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
            }

            Text("Your why decides when it comes back. Say nothing and it comes back tomorrow.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.quiet)
                .lineSpacing(2)

            if photoData == nil {
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Keep a photo instead")
                        .font(.system(size: 16, weight: .semibold))
                        .underline()
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.quiet)
                    .font(.system(size: 17))
                    .frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .leading)
                Spacer()
                LidButton(title: "Keep", action: keep)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(Theme.sheet.ignoresSafeArea())
        .presentationDetents([.height(470)])
        .presentationCornerRadius(Metrics.sheetRadius)
        .onAppear { focus = .text }
        .onChange(of: photo) { _, item in
            Task { photoData = try? await item?.loadTransferable(type: Data.self) }
        }
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

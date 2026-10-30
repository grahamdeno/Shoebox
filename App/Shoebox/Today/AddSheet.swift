import SwiftData
import SwiftUI

/// Keep something by hand. Most saves will come from the share sheet or email.
struct AddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let planner: LaterPlanner

    @State private var text = ""
    @State private var why = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep something")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 26)

            field("Link or note", prompt: "Paste a link or write a note", text: $text)
                .onChange(of: text) { _, _ in error = "" }
            field("Why are you keeping it? (optional)", prompt: "Before the trip", text: $why)

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }

            Text("Your why decides when it comes back. Most saves come in from the share sheet or your Shoebox email.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.quiet)
                .lineSpacing(2)

            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.quiet)
                    .font(.system(size: 17))
                    .frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .leading)
                Spacer()
                Button(action: keep) {
                    VStack(spacing: 0) {
                        Theme.lidLip.frame(height: 8)
                        Text("Keep")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.lidInk)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 128, height: 64)
                    .background(Theme.lid)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(Theme.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Metrics.sheetRadius)
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.quiet)
            TextField(prompt, text: text)
                .font(.system(size: 17))
                .padding(14)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        }
    }

    private func keep() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Add a link or a note first"
            return
        }
        let note = why.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let isLink = trimmed.lowercased().hasPrefix("http") && URL(string: trimmed) != nil
        let save: Save
        if isLink, let url = URL(string: trimmed) {
            save = Save(
                title: url.host ?? trimmed,
                note: note,
                source: "You, just now",
                kind: .link,
                urlString: trimmed
            )
        } else {
            let first = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            let title = String(first.first ?? "").prefix(80)
            let rest = first.count > 1 ? String(first[1]) : ""
            save = Save(title: String(title), snippet: rest, note: note, source: "You, just now", kind: .note)
        }
        save.status = .away
        save.returnDate = planner.firstReturn(note: note, now: now)
        context.insert(save)
        dismiss()
    }
}

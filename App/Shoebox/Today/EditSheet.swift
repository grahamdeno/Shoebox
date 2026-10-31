import SwiftData
import SwiftUI
import UIKit

/// Change a post. Laid out like the Keep screen. Everything saves on its own a moment after you stop typing
/// and again the moment you leave, so nothing is lost. Keep is the sure way out: it saves, taps a haptic and
/// the post shows "Saved". Delete is the last word, at the bottom left, within the thumb's reach.
struct EditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    let save: Save
    /// Called once as the screen closes, when anything was changed.
    var onSaved: () -> Void
    /// Delete: the host closes the post and shows Undo.
    var onDelete: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var words: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var date: Date
    @State private var status = "Changes save as you go."
    @State private var anySaved = false
    @State private var deleted = false
    @State private var pending: Task<Void, Never>?
    /// What each field held when last written, so only what you changed is written. A page preview or a date
    /// read in the background while the screen is open is never overwritten by the screen's older copy.
    @State private var startTitle: String
    @State private var startNote: String
    @State private var startWords: String
    @State private var startHasDate: Bool
    @State private var startHasTime: Bool
    @State private var startDate: Date

    private let hadDate: Bool
    private let dateFloor: Date

    init(save: Save, onSaved: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.save = save
        self.onSaved = onSaved
        self.onDelete = onDelete
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        _title = State(initialValue: save.title)
        _note = State(initialValue: save.note)
        _words = State(initialValue: save.body)
        _hasDate = State(initialValue: save.eventDate != nil)
        _hasTime = State(initialValue: save.eventHasTime)
        _date = State(initialValue: save.eventDate ?? tomorrow)
        _startTitle = State(initialValue: save.title)
        _startNote = State(initialValue: save.note)
        _startWords = State(initialValue: save.body)
        _startHasDate = State(initialValue: save.eventDate != nil)
        _startHasTime = State(initialValue: save.eventHasTime)
        _startDate = State(initialValue: save.eventDate ?? tomorrow)
        hadDate = save.eventDate != nil
        dateFloor = Calendar.current.startOfDay(for: min(save.eventDate ?? Date(), Date()))
    }

    /// Your own writing can be edited in full. A page's text is the page's, so it is left alone.
    private var editsWords: Bool { save.kind == .note || save.kind == .quote }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormTopBar(leading: "Close", onLeading: { dismiss() }, trailing: "Keep", onTrailing: keep)
                .padding(.top, 14)

            Text("Edit")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.formInk)
                .padding(.top, 28)

            Text(status)
                .font(.system(size: 15, weight: status == "Saved" ? .semibold : .regular))
                .foregroundStyle(status == "Saved" ? Theme.formAction : Theme.formQuiet)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LineField(label: "Title") {
                        TextField("", text: $title, prompt: formPrompt("Title"), axis: .vertical)
                            .lineLimit(1...3)
                    }
                    .padding(.top, 28)

                    if editsWords {
                        LineField(label: "Words") {
                            TextField("", text: $words, prompt: formPrompt("What you wrote"), axis: .vertical)
                                .lineLimit(1...8)
                        }
                        .padding(.top, 26)
                    }

                    LineField(label: "Why you kept it") {
                        TextField("", text: $note, prompt: formPrompt("Optional. Before the trip"))
                    }
                    .padding(.top, 26)

                    LineField(label: "The date it is about") {
                        dateRow
                    }
                    .padding(.top, 26)
                    Text("It comes back 5 days before, 1 day before and on the day.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.formQuiet)
                        .padding(.top, 8)

                    Color.clear.frame(height: 90)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.formGround.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .bottomLeading) {
            // Within the thumb's reach, away from Keep at the top.
            Button(action: delete) {
                Text("Delete")
                    .font(.system(size: 17, weight: .semibold))
                    .underline()
                    .foregroundStyle(Theme.formQuiet)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.formGround)
        .onChange(of: title) { _, _ in changed() }
        .onChange(of: note) { _, _ in changed() }
        .onChange(of: words) { _, _ in changed() }
        .onChange(of: hasDate) { _, _ in changed() }
        .onChange(of: hasTime) { _, _ in changed() }
        .onChange(of: date) { _, _ in changed() }
        .onChange(of: phase) { _, p in if p != .active { commit() } }
        .onDisappear {
            pending?.cancel()
            commit()
            if anySaved && !deleted { onSaved() }
        }
    }

    private var dateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasDate {
                DatePicker("", selection: $date, in: dateFloor..., displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.formAction)
                HStack(spacing: 22) {
                    word(hasTime ? "No time" : "Add a time") { hasTime.toggle() }
                    word("Clear date") { hasDate = false; hasTime = false }
                }
            } else {
                word("Add a date") { hasDate = true }
            }
        }
        .font(.system(size: 17))
    }

    private func word(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .underline()
                .foregroundStyle(Theme.formInk)
                .frame(minHeight: Metrics.touchMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Saving

    /// Something changed: save it a moment after typing stops.
    private func changed() {
        status = "Changes save as you go."
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { commit() }
        }
    }

    /// Writes what is on screen into the post, only if it differs. Returns true when something was written.
    @discardableResult
    private func commit() -> Bool {
        guard !deleted, save.deletedAt == nil, save.modelContext != nil else { return false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        var wrote = false
        var textChanged = false

        if title != startTitle { save.title = t; startTitle = title; wrote = true; textChanged = true }
        if note != startNote { save.note = n; startNote = note; wrote = true; textChanged = true }
        if editsWords, words != startWords { save.body = w; startWords = words; wrote = true; textChanged = true }

        let dateEdited = hasDate != startHasDate || hasTime != startHasTime || (hasDate && date != startDate)
        if dateEdited {
            let newHasTime = hasDate && hasTime
            save.eventDate = hasDate ? (newHasTime ? date : Calendar.current.startOfDay(for: date)) : nil
            save.eventHasTime = newHasTime
            if !hasDate { save.otherDatesRaw = "" }
            startHasDate = hasDate; startHasTime = hasTime; startDate = date
            comeBackBeforeTheDate()
            wrote = true
        } else if textChanged, !hadDate, !hasDate, save.eventDate == nil, DateReader.apply(to: save, asOf: Date()) {
            // New words that name a date still ahead, and you did not clear one: read it, as when a post is kept.
            let e = save.eventDate ?? date
            startHasDate = true; startHasTime = save.eventHasTime; startDate = e
            hasDate = true; hasTime = save.eventHasTime; date = e
            comeBackBeforeTheDate()
        }

        guard wrote else { return false }
        save.updatedAt = Date()
        try? context.save()
        anySaved = true
        status = "Saved"
        return true
    }

    /// A post that is waiting comes back before its date.
    private func comeBackBeforeTheDate() {
        guard let event = save.eventDate, save.status == .away, let due = save.returnDate else { return }
        let now = Date()
        if let first = SaveActions().reminders(for: event).first(where: { $0 > now }), first < due {
            save.returnDate = first
        }
    }

    /// The sure way out: saved, a tap you can feel, and the post says "Saved".
    private func keep() {
        guard !deleted else { return }
        pending?.cancel()
        commit()
        anySaved = true
        dismiss()
    }

    private func delete() {
        // Once only: a second tap would take its Undo copy after the delete, and Undo would do nothing.
        guard !deleted else { return }
        pending?.cancel()
        deleted = true
        onDelete()
        dismiss()
    }
}

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ShoeboxCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = Prefs.load()
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var includeAccount = false
    @State private var confirmErase = false
    @State private var calendarOn = CalendarReader.allowed
    @State private var screenshots = Screenshots.on

    var body: some View {
        Form {
            Section("Look") {
                Picker("Palette", selection: Binding(get: { prefs.palette }, set: { prefs.palette = $0; model.setPalette(Palette(rawValue: $0) ?? .plum) })) {
                    Text("Plum and Peach").tag("plum")
                    Text("Midnight Gold").tag("gold")
                }
            }
            Section {
                time("Weekdays", \.weekdayIssue)
                time("Weekends", \.weekendIssue)
            } header: { Text("The morning Issue") } footer: { Text("Today's few, as your reasons. A quiet morning has none.") }
            Section {
                time("Starts", \.homeEveningStart)
                time("Ends", \.homeEveningEnd)
                Button("Set back to 6:00 to 8:30 PM") {
                    prefs.homeEveningStart = .init(hour: 18, minute: 0); prefs.homeEveningEnd = .init(hour: 20, minute: 30); prefs.homeAnswers = []; commit()
                }
            } header: { Text("Evening at home") } footer: { Text("\u{201C}At dinner\u{201D} and \u{201C}with the kids\u{201D} come back here. It moves with when you answer. Shoebox doesn't use your location.") }
            Section {
                Toggle("Read my calendar", isOn: Binding(get: { calendarOn }, set: { on in
                    if on { Task { calendarOn = await CalendarReader.requestAccess(); await model.refresh() } }
                    else if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }))
            } footer: { Text("So \u{201C}before the planning meeting\u{201D} comes back just before it. Your calendar never leaves your iPhone.") }
            Section {
                Toggle("Read new screenshots", isOn: Binding(get: { screenshots }, set: { on in
                    if on { Task { screenshots = await Screenshots.turnOn() } } else { Screenshots.turnOff(); screenshots = false }
                }))
            } footer: { Text("A screenshot with a date, a form, an address or a list is kept and comes back in time. Read on your iPhone; others are left alone.") }
            if let address = prefs.inboxAddress {
                Section {
                    Text(address).textSelection(.enabled)
                    Button("Copy") { UIPasteboard.general.string = address }
                } header: { Text("Your Shoebox email address") } footer: { Text("Forward anything to it. Your note above the forward becomes the reason.") }
            }
            Section {
                Toggle("Turn school newsletters into posts", isOn: Binding(get: { prefs.schoolOn }, set: { prefs.schoolOn = $0; commit() }))
                if prefs.schoolOn {
                    TextField("Child's first name", text: Binding(get: { prefs.schoolChild }, set: { prefs.schoolChild = $0; prefs.save() }))
                    TextField("School's short name", text: Binding(get: { prefs.schoolName }, set: { prefs.schoolName = $0; prefs.save() }))
                    TextField("What matters: grade, teams, activities", text: Binding(get: { prefs.schoolAbout }, set: { prefs.schoolAbout = $0; prefs.save() }), axis: .vertical)
                    TextField("Other words in school mail (mascot, district)", text: Binding(get: { prefs.schoolWords.joined(separator: ", ") },
                        set: { prefs.schoolWords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; prefs.save() }))
                }
            } header: { Text("School email") } footer: { Text("Forward newsletters to your Shoebox address. Each piece for your child becomes its own save. Their name is replaced before anything is sent to AI.") }
            Section {
                Toggle("Use Shoebox's AI when needed", isOn: Binding(get: { prefs.aiConsent.map { !["", "0", "no", "false", "off"].contains($0.lowercased()) } ?? false },
                                                                      set: { prefs.aiConsent = $0 ? "1" : "0"; commit() }))
            } footer: { Text("For school newsletters. Only the words it needs are sent, with your child's name replaced, and nothing is kept. Off keeps everything on your iPhone.") }
            Section("Your saves") {
                Button("Import a backup") { importing = true }
                Toggle("Include my email address and AI sign-up", isOn: $includeAccount)
                Button("Export a backup") {
                    do { exportURL = try Exporter.export(Keeper(context: context), includeAccount: includeAccount) }
                    catch { message = "The backup couldn't be made: \(error.localizedDescription)" }
                }
                if let exportURL { ShareLink(item: exportURL) { Text("Save or send the backup") } }
                Button("Delete everything", role: .destructive) { confirmErase = true }
            }
            Section("Privacy, in plain words") {
                ForEach(Self.promises, id: \.self) { Text($0).type(.body) }
            }
            if let message { Section { Text(message).type(.body) } }
        }
        .scrollContentBackground(.hidden)
        .background(roles.surface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                do { message = try ImportService.importFile(url, keeper: Keeper(context: context)).text; Task { await model.refresh() } }
                catch { message = "That file isn't a Shoebox backup." }
            case .failure: message = "That file couldn't be opened."
            }
        }
        .confirmationDialog("Delete everything?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete every save", role: .destructive) {
                Keeper(context: context).deleteEverything(); Task { await model.refresh() }; message = "Everything is deleted from this iPhone."
            }
        } message: { Text("Every save, photo and file on this iPhone. This can't be undone. Export a backup first if you might want them.") }
    }

    private func time(_ label: String, _ key: WritableKeyPath<Prefs, DayTimeValue>) -> some View {
        DatePicker(label, selection: Binding(
            get: { prefs[keyPath: key].date(on: .now) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                prefs[keyPath: key] = DayTimeValue(hour: c.hour ?? 7, minute: c.minute ?? 0); commit()
            }), displayedComponents: .hourAndMinute)
    }

    private func commit() { prefs.save(); Task { await model.refresh() } }

    /// SPEC 10, as promises.
    static let promises = [
        "Your saves stay on your iPhone. There's no account.",
        "Your calendar is read on your iPhone and never sent anywhere.",
        "Your voice is turned into words on your iPhone. Nothing is recorded or sent.",
        "Shoebox doesn't use your location.",
        "When AI is needed and your iPhone can't do it, only the words it needs are sent, and nothing is kept.",
        "A child's name is replaced before any school email goes to AI.",
        "Shoebox never books, pays, sends or deletes on its own.",
        "Delete everything removes it from your iPhone at once.",
    ]
}

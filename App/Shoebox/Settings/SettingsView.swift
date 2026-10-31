import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Save]

    @State private var perDay = Prefs.perDay
    @State private var appearance = Prefs.appearance
    @State private var stock = Prefs.stockPictures
    @State private var time = DailyTime.date(fromMinute: Prefs.dailyMinute)
    @State private var notificationsOn = Prefs.notificationsOn
    @State private var address = Prefs.inboxAddress
    @State private var firstName = ""
    @State private var addressNote = ""
    @State private var importing = false
    @State private var importNote = ""
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var showMoves = false
    @State private var pickingTime = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .trailing)
                }
                .padding(.top, 20)

                section("Each day")
                card {
                row {
                    Text("Coming out each day").foregroundStyle(Theme.ink)
                    Spacer()
                    ForEach([5, 10, Prefs.noLimit], id: \.self) { n in
                        Button(n == Prefs.noLimit ? "All" : "\(n)") { perDay = n; Prefs.perDay = n }
                            .font(.system(size: 17, weight: perDay == n ? .bold : .regular))
                            .foregroundStyle(perDay == n ? Theme.ink : Theme.quiet)
                            .underline(perDay == n)
                            .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin)
                    }
                }
                row {
                    Text("A notification at").foregroundStyle(Theme.ink)
                    Spacer()
                    // A word, not the system's gray time capsule. Tap it for the wheel.
                    Button(time.formatted(date: .omitted, time: .shortened)) {
                        withAnimation(.snappy) { pickingTime.toggle() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                    .underline(pickingTime)
                    .frame(minHeight: Metrics.touchMin)
                }
                if pickingTime {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                row {
                    Text(notificationsOn ? "Notifications are on" : "Notifications are off").foregroundStyle(Theme.ink)
                    Spacer()
                    Button(notificationsOn ? "Turn off" : "Turn on") {
                        Task {
                            if notificationsOn { Prefs.notificationsOn = false; notificationsOn = false }
                            else { notificationsOn = await Notifier.ask() }
                            await Notifier.schedule(context)
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: Metrics.touchMin)
                }
                }

                section("Look")
                card {
                row {
                    Text("Appearance").foregroundStyle(Theme.ink)
                    Spacer()
                    ForEach([(0, "Auto"), (1, "Light"), (2, "Dark")], id: \.0) { value, name in
                        Button(name) { appearance = value; Prefs.appearance = value }
                            .font(.system(size: 17, weight: appearance == value ? .bold : .regular))
                            .foregroundStyle(appearance == value ? Theme.ink : Theme.quiet)
                            .underline(appearance == value)
                            .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin)
                    }
                }
                }

                section("Pictures")
                card {
                    row {
                        Text("A picture for posts without one").foregroundStyle(Theme.ink)
                        Spacer()
                        Button(stock ? "On" : "Off") { stock.toggle(); Prefs.stockPictures = stock }
                            .fontWeight(.semibold).foregroundStyle(Theme.ink)
                            .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin)
                    }
                    note("Your phone writes a few generic words about the post, never names or your text, and Shoebox's server finds a stock photo. Posts about health, money or legal matters are never looked up.")
                }

                section("Your Shoebox email")
                card {
                if let address {
                    note("Forward an email here and it becomes a post. Write a line above the forward to say why.")
                    row {
                        Text(address).foregroundStyle(Theme.ink).textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = address
                            copied = true
                        }
                        .fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin)
                    }
                } else {
                    note("Get your own address and forward emails to it. Each one becomes a post.")
                    row {
                        TextField("Your first name", text: $firstName)
                            .textContentType(.givenName)
                            .foregroundStyle(Theme.ink)
                        Button("Get my address") {
                            Task {
                                switch await Inbox.makeAddress(firstName: firstName) {
                                case .success(let a): address = a; addressNote = ""
                                case .failure(let e): addressNote = e.localizedDescription
                                }
                            }
                        }
                        .fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    }
                    if !addressNote.isEmpty { note(addressNote) }
                }
                }

                section("Backups")
                card {
                note(backupNote)
                row {
                    Button("Bring in a backup") { importing = true }
                        .fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    Spacer()
                }
                if let exportURL {
                    row {
                        ShareLink(item: exportURL) {
                            Text("Save a backup now").fontWeight(.semibold).foregroundStyle(Theme.ink)
                        }
                        .frame(minHeight: Metrics.touchMin)
                        Spacer()
                    }
                }
                if !importNote.isEmpty { note(importNote) }
                }

                section("Help")
                card {
                row {
                    Button("Show the three moves again") { showMoves = true }
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    Spacer()
                }
                note("To save from Safari or any app: tap Share, then Shoebox. If it isn't in the row, swipe to the end, tap More, then Edit, and add Shoebox to your favorites.")
                }

                section("Privacy")
                card {
                note("Your saves stay on this phone. No account, no ads, no tracking. Link previews, stock photo searches (a few generic words only) and your Shoebox email pass through Shoebox's server and aren't kept there.")
                }

                section("Everything")
                card {
                if confirmDelete {
                    note("This deletes all \(all.count) saves on this phone. Your backups in Files and iCloud Drive stay.")
                    row {
                        Button("Delete all \(all.count)") { deleteEverything() }
                            .fontWeight(.semibold).foregroundStyle(Theme.ink)
                            .frame(minHeight: Metrics.touchMin)
                        Spacer()
                        Button("Keep them") { confirmDelete = false }
                            .foregroundStyle(Theme.quiet)
                            .frame(minHeight: Metrics.touchMin)
                    }
                } else {
                    row {
                        Button("Delete everything") { confirmDelete = true }
                            .foregroundStyle(Theme.quiet)
                            .frame(minHeight: Metrics.touchMin)
                        Spacer()
                    }
                }
                }

                Text("Shoebox \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.quiet)
                    .padding(.top, 28)
            }
            .font(.system(size: 17))
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Theme.ground.ignoresSafeArea())
        .onChange(of: time) { _, t in
            Prefs.dailyMinute = DailyTime.minute(of: t)
            Task { await Notifier.schedule(context) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do { importNote = try Backups.importFile(url, context) }
                catch { importNote = "That file isn't a Shoebox backup." }
            case .failure: importNote = "Couldn't open that file."
            }
        }
        .onAppear(perform: prepareExport)
        .fullScreenCover(isPresented: $showMoves) { ThreeMoves(button: "Got it") { showMoves = false } }
    }

    private var backupNote: String {
        if let at = Backups.lastBackupAt {
            return "Shoebox saves a copy every day to Files and iCloud Drive, in Shoebox › Backups. Last copy: \(at.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Shoebox saves a copy every day to Files and iCloud Drive, in Shoebox › Backups. Bring in a Shoebox 1 backup or one of these to restore."
    }

    private func prepareExport() {
        guard let data = Backups.export(context) else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "shoebox-native-backup-\(TodayRules().dayKey(Date())).json")
        if (try? data.write(to: url, options: .atomic)) != nil { exportURL = url }
    }

    private func deleteEverything() {
        // One last copy first, so this can be undone from Files. No copy, no delete.
        guard let data = Backups.export(context),
              Backups.writeCopy(data, named: "shoebox-before-delete-\(Int(Date().timeIntervalSince1970)).json") else {
            importNote = "Couldn't save a backup first, so nothing was deleted."
            confirmDelete = false
            return
        }
        for s in all { context.delete(s) }
        try? context.save()
        Prefs.pickIds = []
        confirmDelete = false
        dismiss()
    }

    /// The group's label: small caps, muted, above its card.
    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium).lowercaseSmallCaps())
            .tracking(0.8)
            .foregroundStyle(Theme.quiet)
            .padding(.leading, 6)
            .padding(.top, 28)
            .padding(.bottom, 8)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.quiet)
            .lineSpacing(2)
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .frame(minHeight: 52)
    }
}

enum DailyTime {
    static func date(fromMinute m: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: m, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    static func minute(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 7) * 60 + (c.minute ?? 30)
    }
}

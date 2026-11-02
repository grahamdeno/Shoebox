import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings: a short list where each row shows its answer. A row opens one small screen: a title and its choices.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Save]

    private enum Page: Hashable { case day, look, pictures, email, backups, help, privacy, deleteAll }

    @State private var page: Page?
    @State private var perDay = Prefs.perDay
    @State private var appearance = Prefs.appearance
    @State private var stock = Prefs.stockPictures
    @State private var time = DailyTime.date(fromMinute: Prefs.dailyMinute)
    @State private var notificationsOn = Prefs.notificationsOn
    @State private var pickingTime = false
    @State private var address = Prefs.inboxAddress
    @State private var firstName = ""
    @State private var addressNote = ""
    @State private var copied = false
    @State private var importing = false
    @State private var importNote = ""
    @State private var exportURL: URL?
    @State private var showMoves = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            if let page {
                screen(page)
                    .transition(.opacity)
            } else {
                root
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
        .font(.system(size: 17))
        .onChange(of: time) { _, t in
            Prefs.dailyMinute = DailyTime.minute(of: t)
            Task { await Notifier.schedule(context) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do { importNote = try Backups.importFile(url, context) }
                catch { importNote = "That isn't a Shoebox backup." }
            case .failure: importNote = "Couldn't open that file."
            }
        }
        .fullScreenCover(isPresented: $showMoves) { ThreeMoves(button: "Got it") { showMoves = false } }
    }

    // MARK: The list

    private var root: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    title("Settings")
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin, alignment: .trailing)
                }
                .padding(.top, 20)

                card {
                    link("Each day", dayAnswer, .day)
                    hair
                    link("Look", ["Auto", "Light", "Dark"][min(max(appearance, 0), 2)], .look)
                    hair
                    link("Pictures", stock ? "On" : "Off", .pictures)
                    hair
                    link("Email", address == nil ? "Set up" : "On", .email)
                    hair
                    link("Backups", backupAnswer, .backups)
                }
                .padding(.top, 22)

                card { link("How to use Shoebox", nil, .help) }
                    .padding(.top, 18)

                HStack(spacing: 22) {
                    quietWord("Privacy") { page = .privacy }
                    quietWord("Delete everything") { page = .deleteAll }
                }
                .padding(.top, 22)
                .padding(.leading, 6)

                Text("Shoebox \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.quiet)
                    .padding(.top, 14)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var dayAnswer: String {
        let n = perDay == Prefs.noLimit ? "All" : "\(perDay)"
        return notificationsOn ? "\(n) · \(time.formatted(date: .omitted, time: .shortened))" : n
    }

    private var backupAnswer: String {
        guard let at = Backups.lastBackupAt else { return "None yet" }
        return Calendar.current.isDateInToday(at) ? "Today" : at.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: One question per screen

    @ViewBuilder
    private func screen(_ p: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { page = nil } label: {
                        Text("‹ Settings")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.quiet)
                            .frame(minHeight: Metrics.touchMin, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 20)

                switch p {
                case .day: dayScreen
                case .look: lookScreen
                case .pictures: picturesScreen
                case .email: emailScreen
                case .backups: backupsScreen
                case .help: helpScreen
                case .privacy: privacyScreen
                case .deleteAll: deleteScreen
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var dayScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Each day")
            question("How many")
            choices {
                ForEach([5, 10, Prefs.noLimit], id: \.self) { n in
                    choice(n == Prefs.noLimit ? "All" : "\(n)", perDay == n) { perDay = n; Prefs.perDay = n }
                }
            }
            question("Remind me")
            choices {
                choice(time.formatted(date: .omitted, time: .shortened), notificationsOn) {
                    if notificationsOn {
                        withAnimation(.snappy) { pickingTime.toggle() }
                    } else {
                        Task {
                            notificationsOn = await Notifier.ask()
                            await Notifier.schedule(context)
                        }
                    }
                }
                choice("Off", !notificationsOn) {
                    Prefs.notificationsOn = false
                    notificationsOn = false
                    pickingTime = false
                    Task { await Notifier.schedule(context) }
                }
            }
            if pickingTime && notificationsOn {
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }

    private var lookScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Look")
            choices {
                ForEach([(0, "Auto"), (1, "Light"), (2, "Dark")], id: \.0) { value, name in
                    choice(name, appearance == value) { appearance = value; Prefs.appearance = value }
                }
            }
            .padding(.top, 24)
        }
    }

    private var picturesScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Pictures")
            question("Find a picture when a post has none")
            choices {
                choice("On", stock) { stock = true; Prefs.stockPictures = true }
                choice("Off", !stock) { stock = false; Prefs.stockPictures = false }
            }
            line("Your words stay on your phone.")
        }
    }

    private var emailScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Email")
            if let address {
                line("Forward an email here to keep it.")
                card {
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
                }
                .padding(.top, 22)
            } else {
                line("Get an address. Forward an email to it to keep it.")
                card {
                    row {
                        TextField("Your first name", text: $firstName)
                            .textContentType(.givenName)
                            .foregroundStyle(Theme.ink)
                        Button("Get address") {
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
                }
                .padding(.top, 22)
                if !addressNote.isEmpty { line(addressNote) }
            }
        }
    }

    private var backupsScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Backups")
            question("Last copy")
            Text(Backups.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "None yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
            card {
                if let exportURL {
                    row {
                        ShareLink(item: exportURL) {
                            Text("Save a copy now").fontWeight(.semibold).foregroundStyle(Theme.ink)
                        }
                        .frame(minHeight: Metrics.touchMin)
                        Spacer()
                    }
                }
                row {
                    Button("Bring one back") { importing = true }
                        .fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    Spacer()
                }
            }
            .padding(.top, 28)
            if !importNote.isEmpty { line(importNote) }
        }
        .onAppear(perform: prepareExport)
    }

    private var helpScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("How to use Shoebox")
            card {
                row {
                    Button("The three moves") { showMoves = true }
                        .fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    Spacer()
                }
            }
            .padding(.top, 24)
            question("Save from any app")
            Text("Tap Share, then Shoebox.")
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
            line("Not in the row? Swipe to the end, tap More, add Shoebox.")
        }
    }

    private var privacyScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Privacy")
            Text("Your posts stay on this phone.")
                .foregroundStyle(Theme.ink)
                .padding(.top, 24).padding(.horizontal, 6)
            line("No account. No ads. No tracking.")
            line("Link previews, stock pictures and your Shoebox email pass through our server. Nothing is kept.")
        }
    }

    private var deleteScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Delete everything")
            question("Delete all \(all.count) posts?")
            choices {
                choice("Delete all \(all.count)", false) { deleteEverything() }
                choice("Keep them", true) { page = nil }
            }
            line("A copy is saved first. Your Shoebox email address is deleted too.")
            if !importNote.isEmpty { line(importNote) }
        }
    }

    // MARK: Actions

    private func prepareExport() {
        // Once, when you open Backups. This copy carries your files too.
        guard exportURL == nil, let data = Backups.export(context, files: true) else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "shoebox-native-backup-\(TodayRules().dayKey(Date())).json")
        if (try? data.write(to: url, options: .atomic)) != nil { exportURL = url }
    }

    private func deleteEverything() {
        // One last copy first, so this can be undone from Files. No copy, no delete.
        guard let data = Backups.export(context, files: true),
              Backups.writeCopy(data, named: "shoebox-before-delete-\(Int(Date().timeIntervalSince1970)).json") else {
            importNote = "Couldn't save a copy first, so nothing was deleted."
            return
        }
        for s in all { context.delete(s) }
        try? context.save()
        Prefs.pickIds = []
        // Ask the server to delete your email address and any mail waiting there. It runs on its own;
        // if the phone is offline the mail still expires there within 30 days.
        if let key = Prefs.inboxKey {
            Task.detached {
                _ = try? await URLSession.shared.data(for: Relay.request("me/delete", method: "POST", body: Data("{}".utf8), key: key))
            }
        }
        Prefs.inboxKey = nil
        Prefs.inboxAddress = nil
        dismiss()
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .semibold))
            .tracking(-0.8)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.top, 28).padding(.bottom, 10).padding(.horizontal, 6)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 14).padding(.horizontal, 6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func choices<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 26) { content() }.padding(.horizontal, 6)
    }

    private func choice(_ text: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 22, weight: on ? .bold : .regular))
                .foregroundStyle(on ? Theme.ink : Theme.quiet)
                .underline(on, color: Theme.ink)
                .frame(minWidth: Metrics.touchMin, minHeight: Metrics.touchMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func link(_ name: String, _ answer: String?, _ target: Page) -> some View {
        Button { page = target } label: {
            HStack(spacing: 10) {
                Text(name).foregroundStyle(Theme.ink)
                Spacer()
                if let answer { Text(answer).foregroundStyle(Theme.quiet).font(.system(size: 15)) }
                Text("›").foregroundStyle(Theme.quiet).font(.system(size: 20))
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hair: some View { Theme.line.frame(height: 1) }

    private func quietWord(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.quiet)
                .frame(minHeight: Metrics.touchMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

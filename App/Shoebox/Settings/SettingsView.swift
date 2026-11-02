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
    @State private var plusOwned = false
    @State private var plusPrice: String?
    @State private var plusNote = ""
    @State private var restoreNote = ""
    @State private var removing = MailboxKeys.pendingDelete() != nil
    @State private var mailFor = Prefs.mailFor
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
        .onAppear { removing = MailboxKeys.pendingDelete() != nil }
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
                    // Plus is offered after the first week, never in the first run (SPEC 9). A phone with an address always sees it.
                    if Plus.isOffered(hasAddress: address != nil) {
                        hair
                        link("Email", address == nil ? "Set up" : "On", .email)
                    }
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

                if Plus.isOffered(hasAddress: address != nil) {
                    quietWord("Restore purchases") { restorePurchases() }
                        .padding(.leading, 6)
                    if !restoreNote.isEmpty { line(restoreNote) }
                }
                // Delete everything asks the relay again until it confirms (D-6).
                if removing { line("Removing your address from the server.") }

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
                // The relay holds no key for this phone yet, or another phone's: mail waits unopened until Plus is restored here.
                if !Prefs.sealingRegistered { line("Mail waits until Shoebox Plus is restored on this phone.") }
            } else if plusOwned {
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
            } else {
                line("Forward an email to your own address to keep it.")
                card {
                    row {
                        Button("Get your address with Shoebox Plus") { buyPlus() }
                            .fontWeight(.semibold).foregroundStyle(Theme.ink)
                            .frame(minHeight: Metrics.touchMin)
                        Spacer()
                        if let plusPrice { Text(plusPrice).foregroundStyle(Theme.quiet).font(.system(size: 15)) }
                    }
                }
                .padding(.top, 22)
                if !plusNote.isEmpty { line(plusNote) }
            }
            question("Who it's about")
            card {
                TextField("Sam, 4th grade: soccer, band", text: $mailFor, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 14)
                    .onChange(of: mailFor) { _, new in Prefs.mailFor = new }
            }
            line("A newsletter makes posts only for their dates.")
            if let unopened = Inbox.unopenedLine() { line(unopened) }
        }
        .task {
            plusOwned = await Plus.proof() != nil
            plusPrice = await Plus.price()
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
            line("Link previews and stock pictures pass through our server and are not kept.")
            line("Forwarded mail is sealed to a key only your phone holds. We can't read it. It waits up to 7 days.")
            Link("Read the privacy policy", destination: URL(string: "https://inmyshoebox.com/privacy")!)
                .fontWeight(.semibold).foregroundStyle(Theme.ink)
                .frame(minHeight: Metrics.touchMin, alignment: .leading)
                .padding(.top, 16).padding(.horizontal, 6)
        }
    }

    private var deleteScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Delete everything")
            question("Delete all \(liveCount) posts?")
            choices {
                choice("Delete all \(liveCount)", false) { deleteEverything() }
                choice("Keep them", true) { page = nil }
            }
            line("A copy is saved first. Your Shoebox email address is deleted too. Your backups stay in Files until you delete them.")
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

    /// Posts that are still there. Ones already deleted (and kept only so Undo works) are not counted.
    private var liveCount: Int { all.filter { $0.deletedAt == nil }.count }

    private func deleteEverything() {
        // 1. One last copy first, so this can be undone from Files. No copy, no delete. The copy never carries the mailbox key.
        guard let data = Backups.export(context, files: true),
              Backups.writeCopy(data, named: "shoebox-before-delete-\(Int(Date().timeIntervalSince1970)).json") else {
            importNote = "Couldn't save a copy first, so nothing was deleted."
            return
        }
        // 2. The posts, "Who it's about", the address and the pick.
        for s in all { context.delete(s) }
        try? context.save()
        Prefs.pickIds = []
        Prefs.pickDay = nil
        Prefs.mailFor = ""
        mailFor = ""
        Prefs.inboxAddress = nil
        Prefs.sealingRegistered = false
        Prefs.unopenedMail = 0
        Prefs.unopenedMailAt = nil
        address = nil
        // 3. The mailbox secret moves to a pending item and the sealing key goes: from here the app has no mailbox.
        guard MailboxKeys.beginDelete() else {
            importNote = "Your posts are deleted. Couldn't finish removing your address. Delete everything again to try."
            return
        }
        // 4. The relay is asked now, and again on every launch and return to the app until it answers 200.
        removing = MailboxKeys.pendingDelete() != nil
        Task { await Inbox.finishPendingDelete(); removing = MailboxKeys.pendingDelete() != nil }
        dismiss()
    }

    private func buyPlus() {
        Task {
            switch await Plus.buy() {
            case .bought: plusOwned = true; plusNote = ""
            case .pending: plusNote = "Waiting for approval."
            case .cancelled: plusNote = ""
            case .failed: plusNote = "Couldn't reach the App Store. Try again in a minute."
            }
        }
    }

    private func restorePurchases() {
        Task {
            let found = await Plus.restore()
            plusOwned = found
            restoreNote = found ? "Shoebox Plus is on." : "No Shoebox Plus found for this Apple Account."
            // An address whose key the relay does not hold yet is registered the next time mail is collected.
            if found, address != nil { await Inbox.collect(context, forceSealing: true); address = Prefs.inboxAddress }
        }
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

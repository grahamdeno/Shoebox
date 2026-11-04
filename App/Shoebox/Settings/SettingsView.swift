import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings, laid out like Scales: short groups under small titles, each row showing its answer. A row opens one
/// small screen: a title and its choices.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Save]

    private enum Page: Hashable { case day, look, pictures, email, backups, help, privacy, deleteAll }

    @State private var page: Page?
    @State private var perDay = Prefs.perDay
    @State private var appearance = Prefs.appearance
    @State private var colors = Prefs.colors
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
    @State private var sandbox = Plus.inSandbox
    @State private var mailFor = Prefs.mailFor
    @State private var importing = false
    @State private var importNote = ""
    @State private var exportURL: URL?

    var body: some View {
        // The same glass as the Shoebox over the blurred Today post; no lid here (SPEC 2.8).
        GlassSheet(inPresentation: true) {
            ZStack {
                if let page {
                    screen(page)
                        .transition(.opacity)
                } else {
                    root
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
        .onAppear { removing = MailboxKeys.pendingDelete() != nil }
        .task { await Plus.checkStore(); sandbox = Plus.inSandbox }
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
    }

    // MARK: The list

    /// Laid out like Scales' Settings: a few short groups under small titles, each row showing its answer, one quiet
    /// line under a group where it helps, and who we are at the end.
    private var root: some View {
        let offered = Plus.isOffered(hasAddress: address != nil, sandbox: sandbox)
        return ScrollView {
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

                group("Your day")
                card {
                    link("Each day", dayAnswer, .day)
                    hair
                    link("Look", (colors == "stone" ? "Stone, " : "") + ["Automatic", "Light", "Dark"][min(max(appearance, 0), 2)], .look)
                    hair
                    link("Pictures", stock ? "On" : "Off", .pictures)
                }

                // Plus is offered after the first week, never in the first run (SPEC 9). A phone with an address always sees it.
                if offered {
                    group("Email")
                    card { link("Your Shoebox address", address == nil ? "Set up" : "On", .email) }
                    note("Forward an email to keep it. Only your phone can read it.")
                }

                group("Back up")
                card { link("Backups", "Automatic", .backups) }
                note(backupWhere)

                group("Help and about")
                card {
                    link("How Shoebox works", nil, .help)
                    hair
                    outside("Send feedback", "mailto:support@inmyshoebox.com?subject=Shoebox%20feedback")
                    hair
                    outside("Support", "https://inmyshoebox.com/support")
                    hair
                    link("Privacy", nil, .privacy)
                    if offered {
                        hair
                        Button { restorePurchases() } label: { rowLabel("Restore purchases", nil, arrow: false) }
                            .buttonStyle(.plain)
                    }
                    hair
                    rowLabel("Version", version, arrow: false)
                }
                if !restoreNote.isEmpty { note(restoreNote) }
                // Delete everything asks the relay again until it confirms (D-6).
                if removing { note("Removing your address from the server.") }

                quietWord("Delete everything") { page = .deleteAll }
                    .padding(.top, 22)
                    .padding(.leading, 6)

                HStack(spacing: 10) {
                    AppLogo(size: 30)
                    Text("Your posts stay on your phone.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.quiet)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(v) (\(b))"
    }

    /// Where and when the daily copy went, in one line.
    private var backupWhere: String {
        let place = Backups.usesICloud ? "Files and iCloud Drive" : "Files"
        guard let at = Backups.lastBackupAt else { return "Shoebox saves a copy to \(place) once a day, once you keep something." }
        let when = Calendar.current.isDateInToday(at) ? "today" : at.formatted(.dateTime.month(.abbreviated).day())
        return "Saved \(when) to \(place)."
    }

    private var dayAnswer: String {
        let n = perDay == Prefs.noLimit ? "All" : "\(perDay)"
        return notificationsOn ? "\(n) · \(time.formatted(date: .omitted, time: .shortened))" : n
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
                ForEach([(0, "Automatic"), (1, "Light"), (2, "Dark")], id: \.0) { value, name in
                    choice(name, appearance == value) { appearance = value; Prefs.appearance = value }
                }
            }
            .padding(.top, 24)
            question("Colors")
            choices {
                choice("Pistachio", colors != "stone") { colors = "pistachio"; Prefs.colors = "pistachio" }
                choice("Stone", colors == "stone") { colors = "stone"; Prefs.colors = "stone" }
            }
            line("Stone is warm grey and graphite, as in Scales.")
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

    /// Backups say they are automatic, like Scales: nothing to do, two plain choices if you want them.
    private var backupsScreen: some View {
        let place = Backups.usesICloud ? "Files and iCloud Drive" : "Files"
        let last = Backups.lastBackupAt.map {
            Calendar.current.isDateInToday($0) ? "today" : $0.formatted(.dateTime.month(.abbreviated).day())
        }
        return VStack(alignment: .leading, spacing: 0) {
            title("Backups")
            Text("Nothing to do here: Shoebox saves a copy once a day and keeps the last 7. Back up now adds a copy of your own that is never replaced." + (last.map { " Last saved \($0) to \(place), Shoebox." } ?? ""))
                .font(.system(size: 16))
                .foregroundStyle(Theme.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14).padding(.horizontal, 6)
            card {
                if let exportURL {
                    ShareLink(item: exportURL) { rowLabel("Back up now", "Save a file", arrow: false) }
                        .buttonStyle(.plain)
                    hair
                }
                Button { importing = true } label: { rowLabel("Restore from a backup", "Choose a file", arrow: false) }
                    .buttonStyle(.plain)
            }
            .padding(.top, 22)
            note("Restoring only adds. It takes any Shoebox backup, old or new.")
            if !importNote.isEmpty { note(importNote) }
        }
        .onAppear(perform: prepareExport)
    }

    /// How Shoebox works, shown, like Scales: each move as a small moving picture, then the few rules that matter.
    private var helpScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("How Shoebox works")
            MoveDemo(move: .up).padding(.top, 22)
            howLine("**Flick up** for the next one.", "It comes back when your reason says, or tomorrow.")
            MoveDemo(move: .down).padding(.top, 26)
            howLine("**Pull down** to put it away.", "You're done with it. It's kept, and search finds it.")
            MoveDemo(move: .tap).padding(.top, 26)
            howLine("**Tap** to open it.", "Edit is there too. Undo lasts five seconds after any move.")
            howLine("**Keep something new:** tap + New, or Share in any app, then Shoebox.",
                    "Not in the row? Swipe to the end, tap More, add Shoebox.")
                .padding(.top, 14)

            Text("Your reason decides when it comes back.")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 34).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 10) {
                rule("**weekend:** Saturday at 9 AM.")
                rule("**tonight** or **dinner:** this evening at 6.")
                rule("**tomorrow** or a day, like **Monday:** that morning at 8.")
                rule("**before Monday:** the evening before, at 6.")
                rule("**Nothing about a time:** tomorrow.")
                rule("**A date in what you keep:** back 5 days before, every day until you put it away.")
            }
            .padding(.top, 14).padding(.horizontal, 6)
        }
    }

    private func howLine(_ head: LocalizedStringKey, _ more: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(head).font(.system(size: 18)).foregroundStyle(Theme.ink)
            Text(more).font(.system(size: 16)).foregroundStyle(Theme.quiet)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12).padding(.horizontal, 6)
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 17)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
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
        Button { page = target } label: { rowLabel(name, answer) }
            .buttonStyle(.plain)
    }

    /// A row that opens something outside the app: mail, or a page.
    private func outside(_ name: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) { rowLabel(name, nil) }
            .buttonStyle(.plain)
    }

    /// One row: its name, its answer in quiet words, and an arrow when it opens a screen.
    private func rowLabel(_ name: String, _ answer: String?, arrow: Bool = true) -> some View {
        HStack(spacing: 10) {
            Text(name).foregroundStyle(Theme.ink)
            Spacer()
            if let answer { Text(answer).foregroundStyle(Theme.quiet).font(.system(size: 15)) }
            if arrow { Text("›").foregroundStyle(Theme.quiet).font(.system(size: 20)) }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    /// A group's small title, above its card.
    private func group(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 26).padding(.bottom, 8).padding(.horizontal, 6)
    }

    /// One quiet line under a card.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8).padding(.horizontal, 6)
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
            .background { GlassCard() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .frame(minHeight: 52)
    }
}

/// A group's card on the glass: a faint Bone fill, a 1 pt highlight along the top, no outline. With Reduce Transparency
/// it is the solid card color.
struct GlassCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if reduceTransparency {
            shape.fill(Theme.card)
        } else {
            shape.fill(Theme.bone.opacity(0.08))
                .overlay(alignment: .top) {
                    shape.stroke(LinearGradient(colors: [Theme.bone.opacity(0.16), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                .shadow(color: Theme.shade.opacity(0.18), radius: 9, y: 8)
        }
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

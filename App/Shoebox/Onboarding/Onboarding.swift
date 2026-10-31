import SwiftData
import SwiftUI

/// First run. One idea per screen, one clear choice, the bar across the bottom.
/// 1 Welcome (and what came over from Shoebox 1) · 2 Save from anywhere · 3 When it comes out · 4 The three moves.
struct Onboarding: View {
    @Environment(\.modelContext) private var context
    var onFinish: () -> Void

    @State private var step = 0
    @State private var report = Prefs.importReport
    @State private var firstName = ""
    @State private var address = Prefs.inboxAddress
    @State private var addressNote = ""
    @State private var working = false
    @State private var time = DailyTime.date(fromMinute: Prefs.dailyMinute)

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            switch step {
            case 0: welcome
            case 1: saveFromAnywhere
            case 2: whenItComesOut
            default: ThreeMoves(button: "Try it", onDone: finish)
            }
        }
        .animation(.snappy, value: step)
        .onAppear {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "screen") {
            case "share": step = 1
            case "time": step = 2
            case "learn": step = 3
            default: break
            }
            #endif
        }
        .task { if report == nil { report = await Backups.autoImport(context) } }
    }

    private func next() { withAnimation(.snappy) { step += 1 } }

    private func finish() {
        Prefs.dailyMinute = DailyTime.minute(of: time)
        Prefs.onboarded = true
        onFinish()
    }

    // MARK: Screens

    private var welcome: some View {
        page(button: "Start", action: next) {
            LogoTile(size: 132).padding(.bottom, 16)
            title("Keep it.\nIt comes back to you.")
            para("Save the things you mean to come back to. Each morning a few come out of the box, with your reason on top. Swipe past, put away, or deal with it.")
            if let report {
                Text(report)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.noteInk)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var saveFromAnywhere: some View {
        page(button: "Next", action: next, quiet: ("Skip", next)) {
            title("Save from anywhere.")
            numbered(1, "Tap Share", "In Safari, Photos, or any app.")
            numbered(2, "Tap Shoebox", "Not in the row? Swipe to the end, tap More, then add Shoebox.")
            numbered(3, "Say why, tap Keep", "\"For the trip\" brings it back before the trip.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Or forward email").font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.ink)
                if let address {
                    Text(address)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    Text("Write a line above the forward to say why. Ads are skipped.")
                        .font(.system(size: 15)).foregroundStyle(Theme.quiet)
                } else {
                    HStack(spacing: 12) {
                        TextField("Your first name", text: $firstName)
                            .textContentType(.givenName)
                            .font(.system(size: 17))
                            .padding(12)
                            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                        Button(working ? "Wait" : "Get my address") {
                            working = true
                            Task {
                                switch await Inbox.makeAddress(firstName: firstName) {
                                case .success(let a): address = a; addressNote = ""
                                case .failure(let e): addressNote = e.localizedDescription
                                }
                                working = false
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Metrics.touchMin)
                    }
                    Text(addressNote.isEmpty ? "Your own address. Anything you forward to it becomes a post." : addressNote)
                        .font(.system(size: 15)).foregroundStyle(Theme.quiet)
                }
            }
            .padding(.top, 6)
        }
    }

    private var whenItComesOut: some View {
        page(button: "Turn on", action: {
            Prefs.dailyMinute = DailyTime.minute(of: time)
            Task { _ = await Notifier.ask(); next() }
        }, quiet: ("Not now", next)) {
            title("When should they come out?")
            para("One notification a day, at a time you choose. It says how many came out of the box. Tap it and you're on the first one.")
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pieces

    private func page<Content: View>(button: String, action: @escaping () -> Void, quiet: (String, () -> Void)? = nil,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) { content() }
                .padding(.horizontal, 32)
                .padding(.top, 80)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(leading: quiet?.0, leadingQuiet: true, onLeading: quiet?.1 ?? {},
                      trailing: button, onTrailing: action)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .semibold))
            .tracking(-0.8)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18))
            .lineSpacing(3)
            .foregroundStyle(Theme.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func numbered(_ n: Int, _ head: String, _ text: String) -> some View {
        NumberedStep(n: n, head: head, text: text)
    }
}

struct NumberedStep: View {
    let n: Int
    let head: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(n)")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.ink)
                .raised(18, depth: 0.35)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(head).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.system(size: 16)).lineSpacing(2).foregroundStyle(Theme.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Three moves. That's the whole app."
struct ThreeMoves: View {
    let button: String
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Text("Three moves.\nThat's the whole app.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
            NumberedStep(n: 1, head: "Swipe up", text: "Next one. It comes back when your why says, or tomorrow.")
            NumberedStep(n: 2, head: "Pull down", text: "Into your Shoebox. Done, and kept where you can find it.")
            NumberedStep(n: 3, head: "Tap it", text: "Opens it full screen.")
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(trailing: button, onTrailing: onDone)
        }
    }
}

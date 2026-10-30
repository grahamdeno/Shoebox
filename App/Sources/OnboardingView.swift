import SwiftUI
import SwiftData
import ShoeboxCore

/// First launch: bring 1.0's saves over before anything else (SPEC 11.2), then three short asks.
struct OnboardingView: View {
    let finish: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.roles) private var roles
    @Environment(\.modelContext) private var context
    @State private var step = 0
    @State private var report: String?
    @State private var noBackup = false
    @State private var importing = false
    @State private var evening = Prefs.load().homeEveningStart.date(on: .now)

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.space5) {
            Spacer()
            switch step {
            case 0: welcome
            case 1: notifications
            case 2: calendar
            default: home
            }
            Spacer()
        }
        .padding(Metric.space6)
        .background(roles.surface.ignoresSafeArea())
        .task { await bringOver() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            if case .success(let url) = result, let o = try? ImportService.importFile(url, keeper: Keeper(context: context)) { report = o.text; noBackup = false }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            Text("Keep it.\nIt comes back to you.").type(.reasonXl)
            Text("Save anything with your reason. Shoebox brings it back once, when it's useful. Ignore it twice and it goes quiet.")
                .type(.body).foregroundStyle(roles.quiet)
            if let report {
                Text(report).type(.body).padding(Metric.space3)
                    .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
            } else if noBackup {
                Button("Your saves from Shoebox 1 are in Files › Shoebox › Backups. Tap here to import them.") { importing = true }
                    .type(.body).foregroundStyle(roles.actText).multilineTextAlignment(.leading)
            }
            Button("Next") { step = 1 }.buttonStyle(ActButtonStyle())
        }
    }

    private var notifications: some View {
        ask(title: "Saves come back as notifications.",
            body: "Answer right on the Lock Screen: done, later or drop. At most four a day, nothing between 9 PM and your morning Issue.",
            button: "Allow notifications") { _ = await Engine.requestPermission() }
    }

    private var calendar: some View {
        ask(title: "\u{201C}Before the meeting\u{201D} means before the meeting.",
            body: "With your calendar, a save for an event comes back in the free minutes before it. Your calendar never leaves your iPhone.",
            button: "Use my calendar") { _ = await CalendarReader.requestAccess() }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            Text("When are you usually home for the evening?").type(.reasonLg)
            Text("\u{201C}At dinner\u{201D} and \u{201C}show the kids\u{201D} come back then. It learns from when you answer.").type(.body).foregroundStyle(roles.quiet)
            DatePicker("Home from", selection: $evening, displayedComponents: .hourAndMinute).type(.body)
            Button("Start") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: evening)
                Prefs.update { p in
                    p.homeEveningStart = .init(hour: c.hour ?? 18, minute: c.minute ?? 0)
                    let endMinutes = min(21 * 60, (c.hour ?? 18) * 60 + (c.minute ?? 0) + 150)
                    p.homeEveningEnd = .init(hour: endMinutes / 60, minute: endMinutes % 60)
                    p.onboarded = true
                }
                Task { await model.refresh() }
                finish()
            }.buttonStyle(ActButtonStyle())
        }
    }

    private func ask(title: String, body: String, button: String, action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            Text(title).type(.reasonLg)
            Text(body).type(.body).foregroundStyle(roles.quiet)
            Button(button) { Task { await action(); step += 1 } }.buttonStyle(ActButtonStyle())
            Button("Not now") { step += 1 }.buttonStyle(QuietButtonStyle())
        }
    }

    private func bringOver() async {
        guard !Prefs.load().importChecked else { return }
        if let text = await ImportService.autoImport(keeper: Keeper(context: context)) { report = text }
        else { noBackup = LegacyWebImport.mightHaveOldSaves }
        await model.refresh()
    }
}

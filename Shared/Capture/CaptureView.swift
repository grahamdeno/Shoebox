import SwiftUI
import ShoeboxCore

/// The capture sheet (Design System: CaptureSheet). What Shoebox found, your reason (typed or spoken), Save.
/// After saving, one line says when it comes back; tapping it offers the Later choices.
struct CaptureView: View {
    let found: String                 // "Link · nytimes.com"
    let title: String
    var initialReason: String = ""
    let onSave: (_ reason: String, _ spoken: Bool) -> PlanOutcome
    let onChange: (LaterChoice) -> PlannedMoment
    let onPick: (Date) -> Void
    let onClose: () -> Void

    @Environment(\.roles) private var roles
    @State private var reason = ""
    @State private var spoken = false
    @State private var outcome: PlanOutcome?
    @State private var line = ""
    @State private var choosing = false
    @State private var picking = false
    @State private var picked = Date.now.addingTimeInterval(3600)
    @State private var dictation = Dictation()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            HStack(spacing: Metric.space2) {
                AppMark()
                Text(found).type(.meta).foregroundStyle(roles.quiet).lineLimit(1)
                Spacer()
                Button("Cancel", action: onClose).buttonStyle(QuietButtonStyle())
            }
            if !title.isEmpty {
                Text(title).type(.label).foregroundStyle(roles.quiet).lineLimit(2)
            }
            if let outcome { saved(outcome) } else { editing }
        }
        .padding(Metric.space5)
        .background(roles.surface)
        .onAppear {
            reason = initialReason
            typing = initialReason.isEmpty
        }
        .onChange(of: dictation.heard) { _, new in if !new.isEmpty { reason = new; spoken = true } }
    }

    // MARK: Before saving

    private var editing: some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            VStack(alignment: .leading, spacing: Metric.space2) {
                Text("Why are you keeping it?").type(.label).foregroundStyle(roles.quiet)
                HStack(alignment: .top, spacing: Metric.space2) {
                    TextField("", text: $reason, prompt: Text("For Thursday's meeting").foregroundStyle(roles.quiet), axis: .vertical)
                        .type(.reasonMd)
                        .foregroundStyle(roles.text)
                        .lineLimit(1...4)
                        .focused($typing)
                        .submitLabel(.done)
                        .onChange(of: reason) { _, new in if new.count > 140 { reason = SpokenReason.clip(new) } }
                        .accessibilityLabel("Your reason")
                    mic
                }
                .padding(Metric.space3)
                .background(roles.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm)
                    .strokeBorder(typing ? roles.focus : roles.controlLine, lineWidth: typing ? 2 : Metric.hairline))
                if dictation.listening {
                    Text("Listening. Let go when you're done.").type(.label).foregroundStyle(roles.quiet)
                } else if dictation.unavailable {
                    Text("Speaking isn't available here. Type it instead.").type(.label).foregroundStyle(roles.quiet)
                }
            }
            Button {
                dictation.stop()
                let o = onSave(reason, spoken)
                outcome = o
                line = o.moment.explanation
                typing = false
            } label: { Text("Keep it") }
            .buttonStyle(ActButtonStyle())
            Text("No reason is fine. Shoebox will pick a good time.").type(.label).foregroundStyle(roles.quiet)
        }
    }

    private var mic: some View {
        Image(systemName: dictation.listening ? "waveform" : "mic")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(roles.text)
            .frame(width: Metric.tap, height: Metric.tap)
            .background(dictation.listening ? roles.fillSoft : .clear, in: RoundedRectangle(cornerRadius: Metric.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
            .scaleEffect(1 + dictation.level * 0.08)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !dictation.listening { typing = false; Task { await dictation.start() } } }
                    .onEnded { _ in dictation.stop() }
            )
            .accessibilityLabel(dictation.listening ? "Stop" : "Hold to say why")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if dictation.listening { dictation.stop() } else { Task { await dictation.start() } } }
    }

    // MARK: After saving

    @ViewBuilder
    private func saved(_ o: PlanOutcome) -> some View {
        VStack(alignment: .leading, spacing: Metric.space4) {
            Text(reason.isEmpty ? (title.isEmpty ? "Kept." : title) : reason)
                .type(.reasonLg).foregroundStyle(roles.text).fixedSize(horizontal: false, vertical: true)
            Button { withAnimation(.easeOut(duration: 0.2)) { choosing.toggle() } } label: {
                HStack(spacing: Metric.space2) {
                    Text(line).type(.body).foregroundStyle(roles.text)
                    Text(o.moment.confidence == .guess ? "Change?" : "Change").type(.label).foregroundStyle(roles.actText)
                }
            }
            .accessibilityHint("Choose another time")

            if case .ask(let choices, _) = o, !choosing {
                choiceRow(choices)
            }
            if case .offerReminder = o {
                Text("This repeats. Shoebox brings it back once; a reminder in Reminders would repeat.")
                    .type(.label).foregroundStyle(roles.quiet)
            }
            if choosing { laterList }
            if picking {
                DatePicker("", selection: $picked, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).labelsHidden()
                Button("Bring it back then") { onPick(picked); line = "Comes back " + Phrases.when(picked); picking = false; choosing = false }
                    .buttonStyle(LineButtonStyle())
            }
            Button("Done", action: onClose).buttonStyle(ActButtonStyle())
        }
    }

    private func choiceRow(_ choices: [String]) -> some View {
        HStack(spacing: Metric.space2) {
            ForEach(choices, id: \.self) { c in
                Button(c) {
                    switch c.lowercased() {
                    case "this weekend": line = onChange(.thisWeekend).explanation
                    case "next month":
                        let d = Self.firstWeekdayNextMonth()
                        onPick(d); line = "Comes back " + Phrases.when(d)
                    default: picking = true
                    }
                }
                .buttonStyle(LineButtonStyle())
            }
        }
    }

    private var laterList: some View {
        VStack(spacing: Metric.space2) {
            ForEach([LaterChoice.tonight, .tomorrowMorning, .thisWeekend, .nextWeek, .youChoose], id: \.self) { c in
                Button(Self.label(c)) { line = onChange(c).explanation; choosing = false }
                    .buttonStyle(LineButtonStyle())
            }
            Button("Pick a time") { picking = true }.buttonStyle(LineButtonStyle())
        }
    }

    /// The first weekday of next month, at the Issue.
    static func firstWeekdayNextMonth(_ cal: Calendar = .current) -> Date {
        let now = Date.now
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var d = cal.date(byAdding: .month, value: 1, to: start) ?? now
        while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return Prefs.load().weekdayIssue.date(on: d, calendar: cal)
    }

    static func label(_ c: LaterChoice) -> String {
        switch c {
        case .tonight: "Tonight"
        case .tomorrowMorning: "Tomorrow morning"
        case .thisWeekend: "This weekend"
        case .nextWeek: "Next week"
        case .youChoose: "You choose"
        }
    }
}

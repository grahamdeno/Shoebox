import SwiftUI
import UIKit

// The writing surface: every screen where you write is the post you are making.
// The post's picture (or Plum lit warm) is the ground, Cancel and Keep are glass words at the top,
// and one Liquid Glass panel holds the words. The panel rides the keyboard. SPEC 2.5.

/// The ground behind a writing screen when there is no post to borrow it from: a picture graded plain
/// and shaded so the glass reads, or Plum lit warm with Sunflower.
struct SurfaceGround: View {
    var picture: UIImage?

    var body: some View {
        ZStack {
            if let picture {
                Color.clear
                    .overlay { Image(uiImage: picture).resizable().scaledToFill() }
                    .clipped()
                Theme.shade.opacity(0.30)
                Theme.plum.opacity(0.30).blendMode(.softLight)
            } else {
                ZStack {
                    Theme.plumNight
                    RadialGradient(colors: [Theme.lid.opacity(0.30), Theme.lid.opacity(0.06), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 620)
                }
            }
            LinearGradient(stops: [.init(color: Theme.shade.opacity(0.30), location: 0),
                                   .init(color: .clear, location: 0.25),
                                   .init(color: .clear, location: 0.45),
                                   .init(color: Theme.shade.opacity(picture == nil ? 0.15 : 0.5), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A word on glass: pressed it shrinks a little. Plain glass, because interactive glass can swallow taps.
struct SurfacePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Cancel (or Close) at the left, Keep at the right, both words on glass like the opened post.
struct SurfaceBar: View {
    var leading: String
    var onLeading: () -> Void
    var trailing: String
    var trailingEnabled: Bool
    var onTrailing: () -> Void

    var body: some View {
        HStack {
            Button(action: onLeading) { word(leading, color: Theme.onPhoto, weight: .regular) }
                .buttonStyle(SurfacePress())
            Spacer()
            Button(action: onTrailing) {
                word(trailing, color: trailingEnabled ? Theme.sunflower : Theme.onPhoto.opacity(0.45), weight: .semibold)
            }
            .buttonStyle(SurfacePress())
            .disabled(!trailingEnabled)
        }
    }

    private func word(_ text: String, color: Color, weight: Font.Weight) -> some View {
        Text(text)
            .font(.system(size: 17, weight: weight))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(minHeight: Metrics.touchMin)
            .glassEffect(.regular.tint(Theme.shade.opacity(0.35)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The one glass panel. It is as tall as its words; when they outgrow the room above the keyboard it scrolls.
struct SurfacePanel<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxHeight: height)
        .glassEffect(.regular.tint(Theme.shade.opacity(0.42)), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

/// The whole screen. The ground fills it; the panel sits at the bottom, in thumb reach, and rises with the keyboard.
struct WritingSurface<Ground: View, Panel: View>: View {
    var leading = "Cancel"
    var trailing = "Keep"
    var canKeep = true
    var onLeading: () -> Void
    var onTrailing: () -> Void
    @ViewBuilder var ground: Ground
    @ViewBuilder var panel: Panel

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            VStack(spacing: 0) {
                SurfaceBar(leading: leading, onLeading: onLeading, trailing: trailing,
                           trailingEnabled: canKeep, onTrailing: onTrailing)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                SurfacePanel { panel }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        // Posts are the same in light and dark, so is the surface.
        .environment(\.colorScheme, .dark)
        .tint(Theme.sunflower)
    }
}

/// A quiet label and the field beside it, on one line: "Why  Sign up for a dish first".
struct SurfaceLine<Field: View>: View {
    var label: String
    /// Your why is Sunflower; other fields are Bone.
    var tint: Color = Theme.sunflower
    @ViewBuilder var field: Field

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.onPhoto.opacity(0.6))
            field
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .tint(Theme.sunflower)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.onPhoto.opacity(0.22)).frame(height: 0.5) }
    }
}

/// A word in the bottom row of the panel.
struct SurfaceWord: View {
    var text: String
    var quiet = false

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .underline()
            .foregroundStyle(quiet ? Theme.onPhoto.opacity(0.6) : Theme.onPhoto)
            .frame(minHeight: Metrics.touchMin)
            .contentShape(Rectangle())
    }
}

// MARK: When it comes back

/// Where you chose to start showing a save. Automatic means your words decide: your reason, a date in the words,
/// or tomorrow.
enum ReturnChoice: Equatable {
    case auto, tomorrow, weekend, nextWeek
    case day(Date)

    /// The morning it starts coming back, or nil to let the words decide.
    func start(now: Date, calendar: Calendar = .current) -> Date? {
        let planner = LaterPlanner(calendar: calendar)
        switch self {
        case .auto: return nil
        case .tomorrow: return planner.match(words: "tomorrow", now: now)?.date
        case .weekend: return planner.fixedOptions(now: now).first?.date
        case .nextWeek: return planner.fixedOptions(now: now).last?.date
        case .day(let d):
            return calendar.date(byAdding: .hour, value: 8, to: calendar.startOfDay(for: d))
        }
    }

    /// A start day you chose wins: the save waits in the Shoebox, out of Today, until that morning.
    func apply(to saves: [Save], now: Date, calendar: Calendar = .current) {
        guard let start = start(now: now, calendar: calendar), start > now else { return }
        for s in saves {
            s.status = .away
            s.returnDate = start
            s.seenOn = nil
            // A date read from the words that falls before the day you chose would retire the post
            // before it ever shows. The day you chose is the one that counts.
            if let event = s.eventDate, event < start {
                s.eventDate = nil
                s.eventHasTime = false
                s.otherDatesRaw = ""
            }
        }
    }
}

/// The line at the bottom right of the panel: when it comes back.
enum ReturnLine {
    static func text(_ choice: ReturnChoice, event: Date?, why: String, now: Date = Clock.now) -> String {
        if let start = choice.start(now: now) { return back(start, now: now) }
        let planner = LaterPlanner()
        if let m = planner.match(words: why, now: now) { return back(m.date, now: now) }
        if let event, let first = SaveActions().reminders(for: event).first(where: { $0 > now }) {
            return back(first, now: now) + " · 5 days before"
        }
        return "Back tomorrow"
    }

    static func back(_ date: Date, now: Date) -> String {
        let label = LaterPlanner().label(for: date, now: now)
        let soft = ["Today", "Tomorrow", "This weekend"].contains(label)
        return "Back " + (soft ? label.lowercased() : label)
    }
}

/// One small screen of choices as words: when should it come back.
struct ReturnSheet: View {
    @Binding var choice: ReturnChoice
    var autoLine: String
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Clock.now)) ?? Clock.now

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("When should it come back?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)
            Text(autoLine)
                .font(.system(size: 15))
                .foregroundStyle(Theme.quiet)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                row("Let my words decide", picked: choice == .auto) { choice = .auto; dismiss() }
                row("Tomorrow", picked: choice == .tomorrow) { choice = .tomorrow; dismiss() }
                row("This weekend", picked: choice == .weekend) { choice = .weekend; dismiss() }
                row("Next week", picked: choice == .nextWeek) { choice = .nextWeek; dismiss() }
                row("Pick a day", picked: { if case .day = choice { return true } else { return false } }()) {
                    withAnimation(.snappy) { picking.toggle() }
                }
                if picking {
                    HStack {
                        DatePicker("", selection: $day, in: tomorrowOn..., displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Theme.accent)
                        Spacer()
                        Button("Use this day") { choice = .day(day); dismiss() }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: Metrics.touchMin)
                    }
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ground.ignoresSafeArea())
        .presentationBackground(Theme.ground)
        .onAppear { if case .day(let d) = choice { day = d; picking = true } }
    }

    private var tomorrowOn: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Clock.now)) ?? Clock.now
    }

    private func row(_ text: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 19, weight: picked ? .bold : .regular))
                .foregroundStyle(picked ? Theme.accent : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

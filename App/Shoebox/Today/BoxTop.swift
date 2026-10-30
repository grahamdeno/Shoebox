import SwiftUI

/// The lid in the bottom-right corner. Tap it for Later. Flick out of it to open the post.
struct BoxTop: View {
    var onTap: () -> Void
    var onFlick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Theme.lidLip.frame(height: Metrics.lidLip)
            Text("Later")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.lidInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Metrics.lidRestWidth, height: Metrics.lidRestHeight)
        .background(Theme.lid)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.lidRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let travel = hypot(value.translation.width, value.translation.height)
                    if travel > 40 { onFlick() }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Later")
        .accessibilityHint("Put this away until a better time")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { onFlick() }
    }
}

/// The Later list. Grows from the lid, or rises from the strip on an opened post.
struct LaterList: View {
    let suggestion: LaterSuggestion
    let options: [LaterSuggestion]
    var onPick: (LaterSuggestion) -> Void
    var onPickDate: () -> Void
    var onLetGo: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.lidLip.frame(height: Metrics.lidLip)
            Text("Bring it back")
                .font(.system(size: 13))
                .foregroundStyle(Theme.lidQuiet)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)

            Button { onPick(suggestion) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.label)
                        .font(.system(size: 18, weight: .semibold))
                    Text("Suggested, \(suggestion.reason)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.lidQuiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: Metrics.touchMin)
                .background(Theme.lidSuggested)
            }
            .buttonStyle(.plain)

            ForEach(options.filter { $0.label != suggestion.label }, id: \.label) { option in
                row(option.label) { onPick(option) }
            }
            row("Pick a date", action: onPickDate)

            Rectangle().fill(Theme.lidInk.opacity(0.16)).frame(height: 1)
                .padding(.horizontal, 20).padding(.top, 4)

            HStack {
                Button("Let go", action: onLetGo)
                    .foregroundStyle(Theme.lidQuiet)
                Spacer()
                Button("Close", action: onClose)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 15))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.lidInk)
            .padding(.horizontal, 20)
            .frame(minHeight: Metrics.touchMin)
            .padding(.bottom, 6)
        }
        .foregroundStyle(Theme.lidInk)
        .background(Theme.lid)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.lidOpenRadius, style: .continuous))
    }

    private func row(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(minHeight: Metrics.touchMin)
        }
        .buttonStyle(.plain)
    }
}

/// The box from the logo, drawn: an Oceanic box with the Nectarine lid ajar.
struct BoxMark: View {
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(Theme.logoBox)
                .frame(width: size * 0.86, height: size * 0.5)
                .offset(y: size * 0.18)
            VStack(spacing: 0) {
                Theme.lidInk.frame(height: size * 0.055)
                Theme.lid
            }
            .frame(width: size, height: size * 0.24)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.05))
            .rotationEffect(.degrees(-9))
            .offset(y: -size * 0.14)
        }
        .frame(width: size, height: size * 0.8)
        .accessibilityHidden(true)
    }
}

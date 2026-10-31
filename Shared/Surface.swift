import SwiftUI

// Neumorphic surfaces: the shape is the ground color, and depth comes from a light edge
// toward the top left and a soft shade toward the bottom right.

extension View {
    /// Raised out of the ground.
    func raised(_ radius: CGFloat, depth: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.ground)
                .shadow(color: Theme.shadeSide, radius: 16 * depth, x: 10 * depth, y: 12 * depth)
                .shadow(color: Theme.lightSide, radius: 14 * depth, x: -8 * depth, y: -8 * depth)
        )
    }

    /// Pressed into the ground, like a well.
    func inset(_ radius: CGFloat, fill: Color = Theme.ground) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill
                    .shadow(.inner(color: Theme.shadeSide, radius: 5, x: 4, y: 4))
                    .shadow(.inner(color: Theme.lightSide, radius: 5, x: -3, y: -3)))
        )
    }

    /// A recessed rim around a photo set into a raised card.
    func recessedRim(_ radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.shadeSide, Theme.lightSide],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 2)
        )
    }
}

/// The bar across the bottom: Nectarine, full width, words on each end.
/// Used on Today (Later, Open), an opened post (Later, Done), sheets and first run.
struct BottomBar: View {
    var leading: String?
    var leadingQuiet = false
    var onLeading: () -> Void = {}
    var trailing: String
    var onTrailing: () -> Void

    var body: some View {
        HStack {
            if let leading {
                Button(action: onLeading) {
                    Text(leading)
                        .fontWeight(leadingQuiet ? .regular : .semibold)
                        .foregroundStyle(leadingQuiet ? Theme.lidQuiet : Theme.lidInk)
                        .frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            Spacer()
            Button(action: onTrailing) {
                Text(trailing)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.lidInk)
                    .frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .font(.system(size: 18))
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(BarShape())
    }
}

/// The bar's surface: Nectarine with rounded top corners, a lit top edge and a soft lift,
/// running under the home indicator.
struct BarShape: View {
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: Metrics.barRadius, topTrailingRadius: Metrics.barRadius, style: .continuous)
            .fill(Theme.lid
                .shadow(.inner(color: .white.opacity(0.55), radius: 1.5, x: 0, y: 2))
                .shadow(.inner(color: Color(UIColor(hex: 0xB97A3A)).opacity(0.35), radius: 10, x: 0, y: -6)))
            .shadow(color: Theme.shadeSide, radius: 18, x: 0, y: -6)
            .ignoresSafeArea(edges: .bottom)
    }
}

/// The logo box set into a raised tile.
struct LogoTile: View {
    var size: CGFloat = 132

    var body: some View {
        BoxMark(size: size * 0.62)
            .frame(width: size, height: size)
            .raised(size * 0.28)
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
                Theme.logoLid
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

/// A text field pressed into the surface.
struct WellField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .inset(Metrics.fieldRadius)
    }
}

extension View {
    func well() -> some View { modifier(WellField()) }
}

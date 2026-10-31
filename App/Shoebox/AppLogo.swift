import SwiftUI

/// The app's own icon, drawn from the same artwork as the home screen icon:
/// the cards, the Oceanic box and the Nectarine lid on the icon's ground.
struct AppLogo: View {
    var size: CGFloat = 120
    /// Draw the icon tile behind the mark. Off when it sits on a colored surface.
    var tile = true

    var body: some View {
        ZStack {
            if tile {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(Theme.ground)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.03)
            }
            layer("LogoCards", Theme.logoCards)
            layer("LogoBox", Theme.logoBox)
            layer("LogoLid", Theme.logoLid)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func layer(_ name: String, _ color: Color) -> some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.22), radius: size * 0.012, y: size * 0.008)
    }
}

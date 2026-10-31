import SwiftUI
import UIKit

// Colors and sizes from design/tokens.json. Four colors, each with one job:
// Wheat is the light ground, Onyx is the dark ground and the light text, Oceanic is the box
// in the logo, Nectarine is the bottom bar. Your own words get a pale tint of Nectarine.
// Depth comes from soft paired shadows on the ground color (neumorphic), not from more colors.
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
    })
}

enum Theme {
    static let ground = adaptive(light: 0xFFF6E9, dark: 0x0A171D)
    static let sheet = adaptive(light: 0xFFF9F0, dark: 0x111F26)
    static let ink = adaptive(light: 0x0A171D, dark: 0xFFF6E9)
    static let quiet = adaptive(light: 0x5A6B6E, dark: 0x93A4A6)
    static let line = adaptive(light: 0xEADFCC, dark: 0x1E3036)

    // Neumorphic light and shade. Light falls from the top left.
    static let lightSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: 0x1C3038).withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.9)
    })
    static let shadeSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.75) : UIColor(hex: 0x7A5A36).withAlphaComponent(0.22)
    })

    // The user's own words: a pale Nectarine, 28% Nectarine in dark.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 189 / 255, blue: 118 / 255, alpha: 0.28)
            : UIColor(hex: 0xFFD7AA)
    })
    static let noteInk = adaptive(light: 0x0A171D, dark: 0xFFE2BD)

    // The bottom bar. Same Nectarine in both modes.
    static let lid = Color(UIColor(hex: 0xFFBD76))
    static let lidSuggested = Color(UIColor(hex: 0xFFDBB4))
    static let lidInk = Color(UIColor(hex: 0x0A171D))
    static let lidQuiet = Color(UIColor(hex: 0x534938))

    // The box in the logo. Oceanic, and a lighter Oceanic on Onyx so it shows.
    static let logoBox = adaptive(light: 0x003F47, dark: 0x2F7E88)
    static let logoLid = Color(UIColor(hex: 0xFFBD76))
}

enum Metrics {
    /// Outer radius = inner radius + padding, so nested corners stay parallel.
    static let cardRadius: CGFloat = 34
    static let cardInset: CGFloat = 12
    static let photoRadius: CGFloat = 22   // cardRadius - cardInset
    static let sheetRadius: CGFloat = 28
    static let barRadius: CGFloat = 28
    static let fieldRadius: CGFloat = 16
    static let touchMin: CGFloat = 44
}

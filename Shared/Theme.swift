import SwiftUI
import UIKit

// Colors and sizes from design/tokens.json. The palette is four colors. Each has one job:
// Onyx is the text, Wheat is the ground, Oceanic is the box in the logo and the dark ground,
// Nectarine is the box top. Your own words get a pale tint of Nectarine.
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
    static let ground = adaptive(light: 0xFFF6E9, dark: 0x003F47)
    static let sheet = adaptive(light: 0xFFFCF7, dark: 0x144E54)
    static let ink = adaptive(light: 0x0A171D, dark: 0xFFF6E9)
    static let quiet = adaptive(light: 0x5A6B6E, dark: 0xB8C4BF)
    static let line = adaptive(light: 0xEADFCC, dark: 0x295C61)

    // The user's own words: a pale Nectarine, 30% Nectarine in dark.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 189 / 255, blue: 118 / 255, alpha: 0.30)
            : UIColor(hex: 0xFFD7AA)
    })
    static let noteInk = adaptive(light: 0x0A171D, dark: 0xFFE2BD)
    /// The same tint, solid in both modes, for the numbered circles.
    static let noteSolid = Color(UIColor(hex: 0xFFD7AA))

    // The box top. Same Nectarine in both modes.
    static let lid = Color(UIColor(hex: 0xFFBD76))
    static let lidSuggested = Color(UIColor(hex: 0xFFDBB4))
    static let lidInk = Color(UIColor(hex: 0x0A171D))
    static let lidQuiet = Color(UIColor(hex: 0x534938))
    static let lidLip = adaptive(light: 0x003F47, dark: 0x0A171D)

    // The box in the logo. Oceanic, and a lighter Oceanic on the dark ground so it shows.
    static let logoBox = adaptive(light: 0x003F47, dark: 0x2F7E88)
}

enum Metrics {
    static let photoRadius: CGFloat = 18
    static let sheetRadius: CGFloat = 24
    static let lidRadius: CGFloat = 18
    static let lidOpenRadius: CGFloat = 20
    static let lidRestWidth: CGFloat = 128
    static let lidRestHeight: CGFloat = 92
    static let lidInset: CGFloat = 20
    static let lidBottom: CGFloat = 14
    static let lidLip: CGFloat = 9
    static let touchMin: CGFloat = 44
}

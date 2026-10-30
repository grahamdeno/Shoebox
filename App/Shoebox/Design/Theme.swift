import SwiftUI
import UIKit

// Colors and sizes from design/tokens.json. Each color has one job:
// slate is the ground and text, peach is the user's own words, blue is the
// box in the logo, sunflower is the box top.
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
    static let ground = adaptive(light: 0xFFF8F3, dark: 0x36445E)
    static let sheet = adaptive(light: 0xFFFFFF, dark: 0x43526E)
    static let ink = adaptive(light: 0x1E2A3D, dark: 0xF6EEE8)
    static let quiet = adaptive(light: 0x6B7385, dark: 0xC3CBD8)
    static let line = adaptive(light: 0xEEDFD5, dark: 0x4A5975)

    // The user's own words.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 179 / 255, blue: 138 / 255, alpha: 0.30)
            : UIColor(hex: 0xFFC4A3)
    })
    static let noteInk = adaptive(light: 0x1E2A3D, dark: 0xFFE0CC)

    // The box top. Same sunflower in both modes.
    static let lid = Color(UIColor(hex: 0xF2C94C))
    static let lidSuggested = Color(UIColor(hex: 0xFFE6A3))
    static let lidInk = Color(UIColor(hex: 0x1E2A3D))
    static let lidQuiet = Color(UIColor(hex: 0x4A4630))
    static let lidLip = adaptive(light: 0x33415C, dark: 0x1E2A3D)

    // The box in the logo. Blue, never peach.
    static let logoBox = Color(UIColor(hex: 0x33415C))
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

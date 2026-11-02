import SwiftUI
import UIKit

// Colors and sizes from design/tokens.json. Five colors, each with one job, and no black anywhere:
// Wheat is the light ground and the text on dark; Plum Night is the dark ground; Plum Ink is the text on light;
// Plum is the box, in the app and the logo; Nectarine is the lid and your reason.
// Shadows and scrims are a deep plum shade, never black, so even the dark parts of a photo stay warm.
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
    // The palette, by name.
    static let wheat = Color(UIColor(hex: 0xFFF6E9))
    static let plumNight = Color(UIColor(hex: 0x2F2036))
    static let plumInk = Color(UIColor(hex: 0x2A1C30))
    static let plum = Color(UIColor(hex: 0x56395F))
    static let nectarine = Color(UIColor(hex: 0xFFBD76))
    /// The deepest plum: shadows, scrims over photos and glass tints where words sit on a picture.
    static let shade = Color(UIColor(hex: 0x1A1020))

    static let ground = adaptive(light: 0xFFF6E9, dark: 0x2F2036)
    static let sheet = adaptive(light: 0xFFF9F0, dark: 0x36263E)
    static let ink = adaptive(light: 0x2A1C30, dark: 0xFFF6E9)
    static let quiet = adaptive(light: 0x6E6170, dark: 0xBBAEBF)
    static let line = adaptive(light: 0xEADCCB, dark: 0x45344D)
    /// A group's card: one step off the ground. Deeper Wheat in light, lighter Plum Night in dark. No outline.
    static let card = adaptive(light: 0xF3E5D3, dark: 0x3B2A44)
    /// System controls (date pickers, links, selections): Plum on Wheat, Nectarine on Plum Night.
    static let accent = adaptive(light: 0x56395F, dark: 0xFFBD76)
    /// Words that sit on a photo: Wheat, so they stay warm against the picture.
    static let onPhoto = wheat

    // Light and shade. Light falls from the top left; the shade is plum, never black.
    static let lightSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: 0x45334D).withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.9)
    })
    static let shadeSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: 0x1A1020).withAlphaComponent(0.75) : UIColor(hex: 0x7A5A36).withAlphaComponent(0.22)
    })

    // The user's own words: a pale Nectarine, 28% Nectarine in dark.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 189 / 255, blue: 118 / 255, alpha: 0.28)
            : UIColor(hex: 0xFFD7AA)
    })
    static let noteInk = adaptive(light: 0x2A1C30, dark: 0xFFE2BD)

    // The lid. Same Nectarine in both modes.
    static let lid = nectarine
    /// The lid's folded-down edge, a step deeper than the top.
    static let lidLip = Color(UIColor(hex: 0xE9A35C))
    static let lidInk = plumInk

    // Your Shoebox, the box across the bottom of Today: Plum in both modes, like the logo, with Wheat words.
    static let boxGlass = plum
    static let boxText = wheat

    // The logo. The box is Plum; on the dark ground it lifts one step so it still shows at icon size.
    static let logoBox = adaptive(light: 0x56395F, dark: 0x6B4A76)
    static let logoLid = nectarine
    static let logoCards = adaptive(light: 0x6E6170, dark: 0xC9BCCB)

    // Writing screens (Keep something, the share sheet): full screen on the app's own ground,
    // hairline fields, words for actions. Laid out like Scales.
    static let formGround = ground
    static let formInk = ink
    static let formQuiet = quiet
    static let formLine = adaptive(light: 0xDCCAB8, dark: 0x4A3852)
    static let formAction = adaptive(light: 0x2A1C30, dark: 0xFFBD76)
}

enum Metrics {
    /// Outer radius = inner radius + padding, so nested corners stay parallel.
    static let cardRadius: CGFloat = 20
    static let cardInset: CGFloat = 8
    static let photoRadius: CGFloat = 12   // cardRadius - cardInset
    static let sheetRadius: CGFloat = 28
    static let barRadius: CGFloat = 28
    static let fieldRadius: CGFloat = 16
    static let touchMin: CGFloat = 44
}

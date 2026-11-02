import SwiftUI
import UIKit

// Colors and sizes from design/tokens.json. Plum is the dark ground and the light-mode box; Bone is the text on dark,
// the dark-mode box and the words on photos; Sunflower is the lid and your reason on dark; Plum Ink is the text on light.
// Pistachio is the light ground and the family of tints around it. No black anywhere: shadows and scrims are a deep plum.
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
    static let plum = Color(UIColor(hex: 0x3B2240))
    static let plumDeep = Color(UIColor(hex: 0x23132A))
    static let bone = Color(UIColor(hex: 0xF1E9D8))
    static let plumInk = Color(UIColor(hex: 0x2A1E2E))
    static let sunflower = Color(UIColor(hex: 0xF9C93A))
    static let pistachio = Color(UIColor(hex: 0xF6F3E8))
    /// Brick: the one red, only for Delete. Bone words on it read at about 5.7 to 1.
    static let brick = Color(UIColor(hex: 0xA8402F))
    /// The deepest plum: shadows, scrims over photos and glass tints where words sit on a picture.
    static let shade = Color(UIColor(hex: 0x1A1020))

    static let ground = adaptive(light: 0xF6F3E8, dark: 0x3B2240)
    static let sheet = adaptive(light: 0xFBF9F1, dark: 0x442B4B)
    static let ink = adaptive(light: 0x2A1E2E, dark: 0xF1E9D8)
    static let quiet = adaptive(light: 0x6A6070, dark: 0xBBA7BE)
    static let line = adaptive(light: 0xDEDAC9, dark: 0x54405A)
    /// A group's card: one step off the ground. A deeper Pistachio in light, a lighter Plum in dark. No outline.
    static let card = adaptive(light: 0xE8ECDA, dark: 0x4A3352)
    /// System controls (date pickers, links, selections): Plum on Pistachio, Sunflower on Plum.
    static let accent = adaptive(light: 0x3B2240, dark: 0xF9C93A)
    /// Words that sit on a photo: Bone, so they stay warm against the picture.
    static let onPhoto = bone
    /// The ground of a post with no picture, and of the writing sheets: Plum in both modes, as posts are.
    static let plumNight = plum

    // Light and shade. Light falls from the top left; the shade is plum, never black.
    static let lightSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: 0x543A5C).withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.9)
    })
    static let shadeSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: 0x1A1020).withAlphaComponent(0.75) : UIColor(hex: 0x3B2240).withAlphaComponent(0.20)
    })

    // The user's own words: a Pistachio tint in light, 28% Pistachio in dark.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0xB9C9A3).withAlphaComponent(0.28)
            : UIColor(hex: 0xE3EBD7)
    })
    static let noteInk = adaptive(light: 0x2A1E2E, dark: 0xE3EBD7)

    // The lid. Same Sunflower in both modes.
    static let lid = sunflower
    /// The lid's folded-down edge, a step deeper than the top.
    static let lidLip = Color(UIColor(hex: 0xD4A21E))
    static let lidInk = plumInk

    // Your Shoebox, the box across the bottom of Today: Plum with Bone words in light, Bone with Plum words in dark, like the logo.
    static let boxGlass = adaptive(light: 0x3B2240, dark: 0xF1E9D8)
    static let boxText = adaptive(light: 0xF1E9D8, dark: 0x3B2240)

    // The logo. The box is Plum on the light tile and Bone on the Plum tile, so it shows at icon size.
    static let logoBox = adaptive(light: 0x3B2240, dark: 0xF1E9D8)
    static let logoLid = sunflower
    static let logoTile = adaptive(light: 0xF1E9D8, dark: 0x3B2240)
    static let logoCards = adaptive(light: 0xA798AD, dark: 0x8E7A92)

    // Writing screens (Keep something, the share sheet): full screen on the app's own ground,
    // hairline fields, words for actions. Laid out like Scales.
    static let formGround = ground
    static let formInk = ink
    static let formQuiet = quiet
    static let formLine = adaptive(light: 0xCFCBB6, dark: 0x5E4965)
    static let formAction = adaptive(light: 0x2A1E2E, dark: 0xF9C93A)
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

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

/// One color in each set of colors: Pistachio (the default) and Stone (warm stone and graphite, the same as Scales).
private func themed(_ pistachio: UInt32, stone: UInt32) -> Color {
    Color(UIColor { _ in UIColor(hex: Theme.isStone ? stone : pistachio) })
}

/// A color for light and dark, in each set of colors.
private func adaptive(light: UInt32, dark: UInt32, stoneLight: UInt32, stoneDark: UInt32) -> Color {
    Color(UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        if Theme.isStone { return UIColor(hex: isDark ? stoneDark : stoneLight) }
        return UIColor(hex: isDark ? dark : light)
    })
}

/// The same in both sets of colors (the logo, which matches the app icon).
private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
    })
}

enum Theme {
    /// True when Settings › Look › Colors is Stone. Read from the App Group, so the share sheet follows it too.
    static var isStone: Bool { AppGroup.defaults.string(forKey: "colors") == "stone" }

    /// The lighter box and sheet glass in dark: lighter Plum, or a step-darker graphite in Stone (Scales' dark rule).
    static let boxDark = themed(plumLight, stone: 0x16181B)

    // The palette, by name.
    static let plum = themed(0x3B2240, stone: 0x23262B)
    static let plumDeep = themed(0x23132A, stone: 0x16181B)
    static let bone = themed(0xF1E9D8, stone: 0xEEEAE2)
    static let plumInk = themed(0x2A1E2E, stone: 0x1F2124)
    static let sunflower = Color(UIColor(hex: 0xF9C93A))
    static let pistachio = themed(0xF6F3E8, stone: 0xC9C6BD)
    /// Brick: the one red, only for Delete. Bone words on it read at about 5.7 to 1.
    static let brick = Color(UIColor(hex: 0xA8402F))
    /// The deepest plum: shadows, scrims over photos and glass tints where words sit on a picture.
    static let shade = themed(0x1A1020, stone: 0x121316)

    static let ground = adaptive(light: 0xF6F3E8, dark: 0x3B2240, stoneLight: 0xC9C6BD, stoneDark: 0x23262B)
    static let sheet = adaptive(light: 0xFBF9F1, dark: 0x442B4B, stoneLight: 0xD3D0C8, stoneDark: 0x2C3036)
    static let ink = adaptive(light: 0x2A1E2E, dark: 0xF1E9D8, stoneLight: 0x1F2124, stoneDark: 0xEEEAE2)
    static let quiet = adaptive(light: 0x5E5468, dark: 0xC4B2C7, stoneLight: 0x48463F, stoneDark: 0xB3B1AB)
    static let line = adaptive(light: 0xDEDAC9, dark: 0x54405A, stoneLight: 0xB3B0A7, stoneDark: 0x3A3D43)
    /// A group's card: one step off the ground. A deeper Pistachio in light, a lighter Plum in dark. No outline.
    static let card = adaptive(light: 0xE8ECDA, dark: 0x4A3352, stoneLight: 0xBDBAB0, stoneDark: 0x2E3238)
    /// System controls (date pickers, links, selections): Plum on Pistachio, Sunflower on Plum.
    static let accent = adaptive(light: 0x3B2240, dark: 0xF9C93A, stoneLight: 0x23262B, stoneDark: 0xF9C93A)
    /// Words that sit on a photo: Bone, so they stay warm against the picture.
    static let onPhoto = bone
    /// The ground of a post with no picture, and of the writing sheets: Plum in both modes, as posts are.
    static let plumNight = plum

    // Light and shade. Light falls from the top left; the shade is plum, never black.
    static let lightSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: Theme.isStone ? 0x3A3D43 : 0x543A5C).withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.9)
    })
    static let shadeSide = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: Theme.isStone ? 0x121316 : 0x1A1020).withAlphaComponent(0.75) : UIColor(hex: Theme.isStone ? 0x23262B : 0x3B2240).withAlphaComponent(0.20)
    })

    // The user's own words: a Pistachio tint in light, 28% Pistachio in dark.
    static let noteFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0xB9C9A3).withAlphaComponent(0.28)
            : UIColor(hex: 0xE3EBD7)
    })
    static let noteInk = adaptive(light: 0x2A1E2E, dark: 0xE3EBD7, stoneLight: 0x1F2124, stoneDark: 0xE3EBD7)

    // The lid. Same Sunflower in both modes.
    static let lid = sunflower
    /// The lid's folded-down edge, a step deeper than the top.
    static let lidLip = Color(UIColor(hex: 0xD4A21E))
    static let lidInk = plumInk

    // Your Shoebox, the box across the bottom of Today: Plum with Bone words in light; in dark a lighter Plum, so the
    // box stands off the ground (2 to 1) without a bright band across a dark screen. The lid stays the one bright mark.
    // Bone words on it read at about 5.8 to 1. Same box as the logo.
    static let plumLight: UInt32 = 0x6A4F73
    static let boxGlass = adaptive(light: 0x3B2240, dark: plumLight, stoneLight: 0x23262B, stoneDark: 0x16181B)
    static let boxText = bone

    // The logo. The box is Plum on the light tile and the lighter Plum on the Plum tile, like the box on Today.
    static let logoBox = adaptive(light: 0x3B2240, dark: plumLight)
    static let logoLid = sunflower
    // In Plum dark the tile is one step lighter than the ground (0x3B2240), or it vanishes into it. Shadow stays the plum shade.
    static let logoTile = adaptive(light: 0xF1E9D8, dark: 0x4A3050)
    static let logoCards = adaptive(light: 0xA798AD, dark: 0xB7A6BA)

    // Writing screens (Keep something, the share sheet): full screen on the app's own ground,
    // hairline fields, words for actions. Laid out like Scales.
    static let formGround = ground
    static let formInk = ink
    static let formQuiet = quiet
    static let formLine = adaptive(light: 0xCFCBB6, dark: 0x5E4965, stoneLight: 0xACA9A0, stoneDark: 0x42464C)
    static let formAction = adaptive(light: 0x2A1E2E, dark: 0xF9C93A, stoneLight: 0x1F2124, stoneDark: 0xF9C93A)
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

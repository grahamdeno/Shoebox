import SwiftUI
import UIKit

/// The box's Sunflower lid, seen from the front (SPEC 2.2): 44 pt tall, 12 pt in from each edge, 8 pt corners,
/// canted on a hinge at its left end. A lighter top face over a deeper lip and a 1 pt highlight along the top.
/// The faces and highlight are separate smooth shapes: a hard stop inside a tilted gradient shows stair-steps.
struct BoxLid: View {
    static let height: CGFloat = 44
    static let inset: CGFloat = 12
    static let radius: CGFloat = 8
    static let restAngle: Double = 2

    /// Degrees up to the right, on top of the rest angle: 1.5 when leaning, 5 when open, 5 more for the Shoebox sheet.
    var extraAngle: Double = 0
    /// Lit with a Sunflower glow: a post is far enough down to drop in.
    var glowing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let lipHeight = Self.height * 0.44
        shape
            .fill(
                LinearGradient(
                    colors: [Color(UIColor(hex: 0xFFEAA8)), Color(UIColor(hex: 0xFBD457)), Theme.lid, Color(UIColor(hex: 0xF7C535))],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(UIColor(hex: 0xD9A722)), Theme.lidLip, Color(UIColor(hex: 0xC2921A))],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: lipHeight)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color(UIColor(hex: 0xFFFAE8)).opacity(0.9)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(UIColor(hex: 0x784F0A)).opacity(0.35)).frame(height: 1)
            }
            .clipShape(shape)
            .frame(height: Self.height)
            .compositingGroup()
            .shadow(color: glowing ? Theme.lid.opacity(0.8) : .clear, radius: glowing ? 15 : 0)
            .shadow(color: Theme.shade.opacity(0.4), radius: 2, y: 3)
            .shadow(color: Theme.shade.opacity(0.55), radius: 10, y: 12)
            .rotationEffect(.degrees(-(Self.restAngle + extraAngle)), anchor: .leading)
            .animation(.easeOut(duration: 0.18), value: extraAngle)
            .animation(.easeOut(duration: 0.18), value: glowing)
    }
}

/// The glass the box rises out of: the lower 360 pt of the screen blurs the post and tints it Plum, clear at the top and
/// nearly solid at the bottom edge, with no edge or outline (SPEC 2.2). With Reduce Transparency it is solid Plum instead.
struct BoxGlass: View {
    static let height: CGFloat = 200
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tint = Theme.boxGlass
        ZStack {
            if reduceTransparency {
                LinearGradient(stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: tint.opacity(0.9), location: 0.5),
                    .init(color: tint, location: 0.75),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                Color.clear.glassEffect(.regular.tint(tint.opacity(0.35)), in: Rectangle())
                LinearGradient(stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: tint.opacity(0.45), location: 0.38),
                    .init(color: tint.opacity(0.8), location: 0.7),
                    .init(color: tint.opacity(0.94), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
        )
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The glass that the Shoebox and Settings are made of: Plum (a lighter Plum in dark) over the blurred post behind.
/// Its content is always read as on dark, so Bone words and quiet lilac stay readable on Plum in either mode.
/// With Reduce Transparency it is solid Plum.
struct GlassSheet<Content: View>: View {
    var topRadius: CGFloat = Metrics.sheetRadius
    /// True when the system presents it as a sheet (Settings): the glass goes in the sheet's own background.
    var inPresentation = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let background = GlassPlumBackground(scheme: scheme, topRadius: topRadius)
        if inPresentation {
            content
                .environment(\.colorScheme, .dark)
                .presentationBackground { background }
        } else {
            content
                .environment(\.colorScheme, .dark)
                .background { background }
        }
    }
}

struct GlassPlumBackground: View {
    let scheme: ColorScheme
    let topRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tint = scheme == .dark ? Theme.boxDark : Theme.plum
        let shape = UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(tint).ignoresSafeArea()
        } else {
            ZStack {
                shape.fill(.regularMaterial).environment(\.colorScheme, .dark)
                Color.clear.glassEffect(.regular.tint(tint.opacity(0.8)), in: shape)
            }
            .overlay(alignment: .top) {
                shape.stroke(LinearGradient(colors: [Theme.bone.opacity(0.18), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            }
            .ignoresSafeArea()
        }
    }
}

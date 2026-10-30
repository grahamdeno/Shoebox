import SwiftUI
import UIKit

/// The palette in use, from settings. Day or night follows the system.
struct ThemeKey: EnvironmentKey {
    static let defaultValue: ColorRoles = ColorRoles.roles(for: .plum)
}

extension EnvironmentValues {
    var roles: ColorRoles {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Theme {
    static var palette: Palette { Palette(rawValue: Prefs.load().palette) ?? .plum }
    static var roles: ColorRoles { ColorRoles.roles(for: palette) }
}

extension Font {
    /// A Shoebox type style. Falls back to the system serif or sans if the bundled font is missing.
    static func shoebox(_ style: TypeStyle) -> Font {
        let name = style.family
        if UIFont(name: name, size: style.size) != nil {
            return .custom(name, size: style.size, relativeTo: style.relativeTo).weight(style.weight)
        }
        return .system(size: style.size, weight: style.weight, design: style.isSerif ? .serif : .default)
    }
}

extension View {
    /// Type style with its line height and (for meta) uppercase tracking.
    func type(_ style: TypeStyle) -> some View {
        self.font(.shoebox(style))
            .lineSpacing(max(0, style.lineHeight - style.size * 1.2))
            .textCase(style.uppercase ? .uppercase : nil)
            .tracking(style.uppercase ? 0.9 : 0)
    }
}

// MARK: Components (design/ and the Design System: Button, Coming back row, capture sheet)

/// The one act-colored thing on a screen.
struct ActButtonStyle: ButtonStyle {
    @Environment(\.roles) private var roles
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.button)
            .padding(.horizontal, Metric.space4)
            .frame(minHeight: Metric.tap)
            .frame(maxWidth: .infinity)
            .foregroundStyle(roles.onAct)
            .background(roles.act.opacity(configuration.isPressed ? 0.88 : 1), in: RoundedRectangle(cornerRadius: Metric.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.actEdge, lineWidth: Metric.hairline))
    }
}

/// Outlined, for Later and the rest.
struct LineButtonStyle: ButtonStyle {
    @Environment(\.roles) private var roles
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.button)
            .padding(.horizontal, Metric.space3)
            .frame(minHeight: Metric.tap)
            .frame(maxWidth: .infinity)
            .foregroundStyle(roles.text)
            .background(configuration.isPressed ? roles.fillSoft : Color.clear, in: RoundedRectangle(cornerRadius: Metric.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(roles.controlLine, lineWidth: Metric.hairline))
    }
}

/// Plain, quiet text, for Drop.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.roles) private var roles
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.button)
            .padding(.horizontal, Metric.space2)
            .frame(minHeight: Metric.tap)
            .foregroundStyle(roles.quiet)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The small app mark on a moment's top line.
struct AppMark: View {
    @Environment(\.roles) private var roles
    var body: some View {
        RoundedRectangle(cornerRadius: Metric.radiusSm)
            .fill(roles.mark)
            .frame(width: Metric.appMark, height: Metric.appMark)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(roles.surface).frame(height: 7).padding(3)
            }
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    @Environment(\.roles) private var roles
    var body: some View { Rectangle().fill(roles.line).frame(height: Metric.hairline) }
}

/// Applies the palette to a whole screen.
struct Themed: ViewModifier {
    let roles: ColorRoles
    func body(content: Content) -> some View {
        content
            .environment(\.roles, roles)
            .tint(roles.act)
            .foregroundStyle(roles.text)
            .background(roles.surface.ignoresSafeArea())
    }
}

extension View {
    func themed(_ roles: ColorRoles = Theme.roles) -> some View { modifier(Themed(roles: roles)) }
}

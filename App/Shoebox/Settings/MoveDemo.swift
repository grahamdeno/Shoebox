import SwiftUI

/// A small looping picture of one move, for Settings › How Shoebox works (like Scales' How it works): a post, the
/// thumb on it, and where the post goes. Still, half way through the move, when Reduce Motion is on.
struct MoveDemo: View {
    enum Move { case up, down, tap }
    let move: Move

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let loop: Double = 2.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.4 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop) / Self.loop
            scene(t)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }

    /// One moment of the loop, t from 0 to 1: rest, the move, gone, then the post comes back.
    @ViewBuilder
    private func scene(_ t: Double) -> some View {
        let p = Self.ease(Self.clamp((t - 0.15) / 0.4))     // the move, 0 to 1
        let back = Self.ease(Self.clamp((t - 0.8) / 0.2))   // the post returning at the end
        let gone = t >= 0.55 && t < 0.8
        let thumb = t > 0.06 && t < 0.58
        switch move {
        case .up:
            let y = t < 0.8 ? -90 * p : 0
            ZStack {
                post.offset(y: y).opacity(t < 0.8 ? (gone ? 0 : 1 - p) : back)
                if thumb { finger.offset(y: 22 + y) }
            }
        case .down:
            let y = t < 0.8 ? 46 * p : 0
            ZStack {
                box.offset(y: 50)
                post.scaleEffect(t < 0.8 ? 1 - 0.45 * p : 1).offset(y: y - 12)
                    .opacity(t < 0.8 ? (gone ? 0 : 1 - p * 0.9) : back)
                if thumb { finger.offset(y: 10 + y) }
            }
        case .tap:
            let press = sin(.pi * Self.clamp((t - 0.25) / 0.25))
            ZStack {
                post.scaleEffect(1 + 0.05 * press)
                if t > 0.12 && t < 0.62 { finger.scaleEffect(1 - 0.2 * press).offset(y: 4) }
            }
        }
    }

    /// A post: the ink color with two lines of words, so it reads in both modes.
    private var post: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.ink)
            .frame(width: 128, height: 58)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Theme.ground.opacity(0.75)).frame(width: 84, height: 6)
                    Capsule().fill(Theme.ground.opacity(0.5)).frame(width: 56, height: 6)
                }
                .padding(.leading, 16)
            }
    }

    private var finger: some View {
        Circle().fill(Theme.quiet.opacity(0.85)).frame(width: 26, height: 26)
    }

    /// The box at the bottom of Today: its Sunflower lid over the box.
    private var box: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.lid).frame(height: 8)
            Rectangle().fill(Theme.boxGlass).frame(height: 14)
        }
        .frame(width: 200)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

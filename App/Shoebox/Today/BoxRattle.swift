import CoreHaptics
import UIKit

/// The feel of a shoebox that has been bumped: a quick run of small knocks that die away,
/// over a low rumble, like things shifting inside.
@MainActor
enum BoxRattle {
    private static var engine: CHHapticEngine?

    /// `strong` for a post dropping into the box, softer for one flicked away.
    static func play(strong: Bool) {
        let scale: Float = strong ? 1.0 : 0.65
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback(scale)
            return
        }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.isAutoShutdownEnabled = true
                e.resetHandler = { [weak e] in try? e?.start() }
                engine = e
            }
            try engine?.start()

            // Knocks: close together at first, then spreading out and fading.
            let knocks: [(t: Double, i: Float, s: Float)] = [
                (0.00, 1.00, 0.90), (0.05, 0.80, 0.70), (0.11, 0.90, 0.85),
                (0.18, 0.60, 0.55), (0.26, 0.55, 0.60), (0.35, 0.35, 0.45), (0.46, 0.20, 0.35),
            ]
            var events = knocks.map { k in
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: k.i * scale),
                                           CHHapticEventParameter(parameterID: .hapticSharpness, value: k.s)],
                              relativeTime: k.t)
            }
            // The rustle underneath.
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35 * scale),
                                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12)],
                                        relativeTime: 0, duration: 0.45))
            let fade = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: 0.45, value: 0)],
                relativeTime: 0)
            let pattern = try CHHapticPattern(events: events, parameterCurves: [fade])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(scale)
        }
    }

    private static func fallback(_ scale: Float) {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        for (i, t) in [0.0, 0.05, 0.11, 0.18, 0.27, 0.37].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                gen.impactOccurred(intensity: CGFloat(max(0.2, (1 - Float(i) * 0.15) * scale)))
            }
        }
    }
}

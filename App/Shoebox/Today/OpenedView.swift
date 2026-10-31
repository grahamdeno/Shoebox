import SwiftUI
import UIKit

/// A post opened full screen: the picture behind, the words on Liquid Glass, and the same two moves as Today
/// as words at the bottom: Not now and Put away.
struct OpenedView: View {
    let save: Save
    var onClose: () -> Void
    var onNotNow: () -> Void
    var onPutAway: () -> Void


    /// The full text with links made tappable: the email, the note, or the page's text.
    private var reading: AttributedString {
        let text = save.body.isEmpty ? save.snippet : save.body
        var out = AttributedString(text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = m.url, let r = Range(m.range, in: text), let ar = Range(r, in: out) else { continue }
                out[ar].link = url
                out[ar].underlineStyle = .single
            }
        }
        return out
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop

            ScrollView {
                VStack(spacing: 16) {
                    // The photo shows through first; the words sit low, like a poster.
                    Color.clear.frame(height: save.imageData == nil ? 120 : 330)

                    VStack(spacing: 8) {
                        Text(save.headline)
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.6)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        Text(save.byline())
                            .font(.system(size: 15))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
                    .padding(.horizontal, 12)

                    if !save.note.isEmpty {
                        Text(save.note)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.lidInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .glassEffect(.regular.tint(Theme.lid.opacity(0.85)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let url = save.url {
                        Link(destination: url) {
                            Text("Open the page on \(save.host ?? "the web")")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(minHeight: Metrics.touchMin)
                                .glassEffect(.regular.tint(Theme.onyx.opacity(0.35)).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    if !reading.characters.isEmpty {
                        Text(reading)
                            .font(.system(size: 18))
                            .lineSpacing(6)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22)
                            .glassEffect(.regular.tint(Theme.onyx.opacity(min(0.7, grade.glassTint + 0.2))), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { strip }

            closeButton

        }
        .environment(\.colorScheme, .dark)
        .task { if save.enrichedAt == nil { await Relay.enrich(save) } }
    }

    /// The photo, full screen and still while the words scroll over it. Without one,
    /// Onyx lit warm from the top corner so the glass still has something to sit on.
    private var backdrop: some View {
        GeometryReader { geo in
            // The words start about 330 pt down, so the subject sits in the space above them.
            PostPhoto(id: save.id, data: save.imageData, topClear: 100, bottomClear: max(0, geo.size.height - 330))
        }
        .ignoresSafeArea()
    }

    private var grade: PhotoGrade { PhotoCache.grade(id: save.id, data: save.imageData) }

    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Metrics.touchMin)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// The two moves, as words on glass.
    private var strip: some View {
        HStack {
            Button(action: onNotNow) {
                Text("Not now").frame(minWidth: 88, minHeight: 52, alignment: .leading).contentShape(Rectangle())
            }
            Spacer()
            Button(action: onPutAway) {
                Text("Put away").frame(minWidth: 88, minHeight: 52, alignment: .trailing).contentShape(Rectangle())
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

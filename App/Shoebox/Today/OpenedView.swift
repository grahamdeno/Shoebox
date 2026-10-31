import SwiftUI
import UIKit

/// A post opened full screen, with the bar across the bottom: Later and Done.
struct OpenedView: View {
    let save: Save
    let planner: LaterPlanner
    var onClose: () -> Void
    var onDone: () -> Void
    var onLater: (LaterSuggestion) -> Void
    var onPickDate: () -> Void
    var onLetGo: () -> Void

    @State private var laterOpen = false

    private var image: UIImage? { save.imageData.flatMap(UIImage.init(data:)) }

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
                    Color.clear.frame(height: image == nil ? 120 : 330)

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
                            .glassEffect(.regular.tint(Theme.lid.opacity(0.75)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let url = save.url {
                        Link(destination: url) {
                            Text("Open the page on \(save.host ?? "the web")")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(minHeight: Metrics.touchMin)
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    if !reading.characters.isEmpty {
                        Text(reading)
                            .font(.system(size: 17))
                            .lineSpacing(5)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { strip }

            closeButton

            if laterOpen {
                Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { withAnimation(.snappy) { laterOpen = false } }
                LaterList(
                    suggestion: planner.suggestion(for: save, now: Date()),
                    options: planner.fixedOptions(now: Date()),
                    onPick: { onLater($0) },
                    onPickDate: onPickDate,
                    onLetGo: onLetGo,
                    onClose: { withAnimation(.snappy) { laterOpen = false } }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .environment(\.colorScheme, .dark)
        .task { if save.enrichedAt == nil { await Relay.enrich(save) } }
    }

    /// The photo, full screen and still while the words scroll over it. Without one,
    /// a deep Oceanic to Onyx wash so the glass still has something to sit on.
    private var backdrop: some View {
        ZStack {
            if let image {
                Color.clear
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(UIColor(hex: 0x003F47)), Color(UIColor(hex: 0x0A171D))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

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

    /// The bar across the bottom.
    private var strip: some View {
        BottomBar(leading: "Later", onLeading: { withAnimation(.snappy) { laterOpen = true } },
                  trailing: "Done", onTrailing: onDone)
    }
}

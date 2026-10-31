import SwiftUI
import UIKit

/// A post opened full screen: the picture behind (darker than on Today, so the words lead), the words on
/// Liquid Glass, and the same two moves as Today as words at the bottom: Next and Put away.
/// A put away post has one word instead: Bring back. Edit is a word at the top right.
struct OpenedView: View {
    let save: Save
    var onClose: () -> Void
    var onNotNow: () -> Void
    var onPutAway: () -> Void
    var onBringBack: () -> Void
    var onDelete: () -> Void

    @State private var showEdit = false
    @State private var savedFlash = false

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

                    if save.imageSource == "stock", let credit = save.imageCredit {
                        creditLine(credit)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { strip }

            topWords

            if savedFlash {
                VStack {
                    UndoPill(text: "Saved", action: nil).padding(.top, 10)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .task { if save.enrichedAt == nil { await Relay.enrich(save) } }
        // Outside the dark override, so the edit screen follows the app's own look.
        .sheet(isPresented: $showEdit) {
            EditSheet(save: save, onSaved: flashSaved, onDelete: onDelete)
        }
    }

    /// The sure sign that an edit was kept.
    private func flashSaved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) { savedFlash = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation { savedFlash = false }
        }
    }

    /// The photo, full screen and still while the words scroll over it. Without one,
    /// Onyx lit warm from the top corner so the glass still has something to sit on.
    private var backdrop: some View {
        GeometryReader { geo in
            // The words start about 330 pt down, so the subject sits in the space above them.
            ZStack {
                PostPhoto(id: save.id, data: save.imageData, topClear: 100, bottomClear: max(0, geo.size.height - 330))
                // Darker than on Today: a little over everything, a lot behind the words.
                Color.black.opacity(save.imageData == nil ? 0 : 0.22)
                if save.imageData != nil {
                    LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                           .init(color: .black.opacity(0.28), location: 0.34),
                                           .init(color: .black.opacity(0.52), location: 0.7),
                                           .init(color: .black.opacity(0.62), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Pixabay's credit for a stock picture, small, under the words.
    @ViewBuilder
    private func creditLine(_ credit: String) -> some View {
        let text = Text(credit)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.75))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        if let s = save.imageCreditURL, let url = URL(string: s) {
            Link(destination: url) { text.underline() }
        } else {
            text
        }
    }

    private var grade: PhotoGrade { PhotoCache.grade(id: save.id, data: save.imageData) }

    /// Close at the left, Edit at the right.
    private var topWords: some View {
        VStack {
            HStack {
                glassWord("Close", action: onClose)
                Spacer()
                glassWord("Edit") { showEdit = true }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func glassWord(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: Metrics.touchMin)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The two moves, as words on glass. A put away post has one: Bring back.
    private var strip: some View {
        HStack {
            if save.status == .kept {
                Spacer()
                Button(action: onBringBack) {
                    Text("Bring back").frame(minWidth: 88, minHeight: 52, alignment: .trailing).contentShape(Rectangle())
                }
            } else {
                Button(action: onNotNow) {
                    Text("Next").frame(minWidth: 88, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                }
                Spacer()
                Button(action: onPutAway) {
                    Text("Put away").frame(minWidth: 88, minHeight: 52, alignment: .trailing).contentShape(Rectangle())
                }
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

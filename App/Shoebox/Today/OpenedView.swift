import SwiftUI
import UIKit

/// A post opened full screen. The lid comes with it and becomes the bottom strip.
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        VStack(alignment: .leading, spacing: 14) {
                            Text(save.title)
                                .font(.system(size: 28, weight: .semibold))
                                .tracking(-0.5)
                                .foregroundStyle(Theme.ink)
                            if !save.note.isEmpty {
                                Text(save.note)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.noteInk)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
                            }
                            if !save.snippet.isEmpty {
                                Text(save.snippet)
                                    .font(.system(size: 17))
                                    .lineSpacing(5)
                                    .foregroundStyle(Theme.ink)
                            }
                            if let link = save.urlString, let url = URL(string: link) {
                                Link(link, destination: url)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.ink)
                                    .underline()
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 40)
                    }
                }
                .ignoresSafeArea(edges: .top)

                strip
            }

            if laterOpen {
                Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { laterOpen = false }
                LaterList(
                    suggestion: planner.suggestion(for: save, now: Date()),
                    options: planner.fixedOptions(now: Date()),
                    onPick: { onLater($0) },
                    onPickDate: onPickDate,
                    onLetGo: onLetGo,
                    onClose: { laterOpen = false }
                )
                .frame(maxWidth: .infinity)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .transition(.move(edge: .bottom))
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(height: 330).frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: 70)
            }
            Button(action: onClose) {
                Text("Close")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(image == nil ? Theme.ink : .white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Metrics.touchMin)
                    .background(image == nil ? Color.clear : Color.black.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.leading, 12)
            .padding(.top, 54)
        }
    }

    /// The lid, as a full-width strip.
    private var strip: some View {
        VStack(spacing: 0) {
            Theme.lidLip.frame(height: Metrics.lidLip)
            HStack {
                Button { withAnimation(.snappy) { laterOpen = true } } label: {
                    Text("Later").frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .leading)
                }
                Spacer()
                Button(action: onDone) {
                    Text("Done").frame(minWidth: 64, minHeight: Metrics.touchMin, alignment: .trailing)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.lidInk)
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 22)
        }
        .background(Theme.lid)
    }
}

import SwiftUI
import UIKit

/// One post, one screen. A photo when it has one, otherwise type only.
struct PostView: View {
    let save: Save
    let planner: LaterPlanner
    let now: Date

    private var image: UIImage? {
        save.imageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.photoRadius, style: .continuous))
                    .padding(.bottom, 26)
                    .accessibilityHidden(true)
                details(titleSize: 30)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                details(titleSize: 38)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func details(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !save.source.isEmpty {
                Text(save.source)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.quiet)
                    .padding(.bottom, 12)
            }
            if !save.note.isEmpty {
                Text(save.note)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.noteInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 16)
            }
            Text(save.title)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            if !save.snippet.isEmpty {
                Text(save.snippet)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.quiet)
                    .lineSpacing(3)
                    .lineLimit(4)
            }
            if let event = save.eventDate {
                Text("It comes back on its own before \(planner.label(for: event, now: now))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 20)
            }
        }
    }
}

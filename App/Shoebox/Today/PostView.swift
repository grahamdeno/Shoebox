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
                // The picture sits in an overlay so its size never changes the width of the screen.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.photoRadius, style: .continuous))
                    .padding(.top, 20)
                    .padding(.bottom, 26)
                    .accessibilityHidden(true)
                details(titleSize: 30, snippetLines: 3)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                details(titleSize: 38, snippetLines: 6)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func details(titleSize: CGFloat, snippetLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(save.byline(now: now))
                .font(.system(size: 14))
                .foregroundStyle(Theme.quiet)
                .lineLimit(1)
                .padding(.bottom, 12)
            if !save.note.isEmpty {
                Text(save.note)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.noteInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.noteFill, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 16)
            }
            Text(save.headline)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            if !save.snippet.isEmpty {
                Text(save.snippet)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.quiet)
                    .lineSpacing(3)
                    .lineLimit(snippetLines)
                    .padding(.trailing, 40)
            }
            if let event = save.eventDate {
                Text(comesBack(event))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 20)
            }
        }
    }

    /// "Comes back Nov 7, Nov 11 and Nov 12 on its own"
    private func comesBack(_ event: Date) -> String {
        let days = SaveActions().reminders(for: event).filter { $0 > now }
        guard !days.isEmpty else { return "The day is here." }
        let labels = days.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let list = labels.count == 1 ? labels[0] : labels.dropLast().joined(separator: ", ") + " and " + labels[labels.count - 1]
        return "Comes back \(list) on its own"
    }
}

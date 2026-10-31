import SwiftUI
import UIKit

/// One post, full screen: its picture fills the screen and the words sit on Liquid Glass near the bottom.
/// A post with no picture gets a deep Oceanic to Onyx wash so the glass still has something to sit on.
struct PostCard: View {
    let save: Save
    let now: Date
    /// The screen's safe area, because the card itself runs edge to edge.
    var insets: EdgeInsets
    /// Room left at the bottom for the box.
    var bottomRoom: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            PostPhoto(id: save.id, data: save.imageData)
            words
                .padding(.horizontal, 12)
                .padding(.bottom, insets.bottom + bottomRoom + 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.onyx)
        .environment(\.colorScheme, .dark)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !save.note.isEmpty {
                Text(save.note)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.lid)
            }
            Text(save.headline)
                .font(.system(size: save.imageData == nil ? 34 : 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if !save.snippet.isEmpty {
                Text(save.snippet)
                    .font(.system(size: 16))
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3)
            }
            if let event = save.eventDate {
                Text(comesBack(event))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.lid)
            }
            Text(save.byline(now: now))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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

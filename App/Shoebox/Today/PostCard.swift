import SwiftUI
import UIKit

/// One post, full screen: its picture fills the screen and the words sit on Liquid Glass near the bottom.
/// A post with no picture gets Plum Night lit warm from the top corner so the glass still has something to sit on.
struct PostCard: View {
    let save: Save
    let now: Date
    /// The screen's safe area, because the card itself runs edge to edge.
    var insets: EdgeInsets
    /// Room left at the bottom for the box.
    var bottomRoom: CGFloat

    var body: some View {
        let grade = PhotoCache.grade(id: save.id, data: save.imageData)
        ZStack(alignment: .bottom) {
            // The subject sits in the clear space above the words, below the top buttons.
            PostPhoto(id: save.id, data: save.imageData,
                      topClear: insets.top + 64, bottomClear: insets.bottom + bottomRoom + 16 + 270)
            words(grade)
                .padding(.horizontal, 12)
                .padding(.bottom, insets.bottom + bottomRoom + 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.plumNight)
        .environment(\.colorScheme, .dark)
    }

    private func words(_ grade: PhotoGrade) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !save.note.isEmpty {
                Text(save.note)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.lid)
                    .shadow(color: Theme.shade.opacity(0.35), radius: 1.5, y: 1)
            }
            Text(save.headline)
                .font(.system(size: save.imageData == nil ? 34 : 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.onPhoto)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: Theme.shade.opacity(0.4), radius: 2, y: 1)
            if !save.snippet.isEmpty {
                Text(save.snippet)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.onPhoto.opacity(0.95))
                    .lineLimit(3)
                    .shadow(color: Theme.shade.opacity(0.35), radius: 1.5, y: 1)
            }
            if let event = save.eventDate {
                Text(comesBack(event))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.lid)
            }
            Text(save.byline(now: now))
                .font(.system(size: 13))
                .foregroundStyle(Theme.onPhoto.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular.tint(Theme.shade.opacity(grade.glassTint)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "Oct 30 at 4:00 PM. Back Oct 25, Oct 29 and Oct 30."
    private func comesBack(_ event: Date) -> String {
        let when = save.eventHasTime
            ? event.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                .replacingOccurrences(of: ", ", with: " at ")
            : event.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let days = SaveActions().reminders(for: event).filter { $0 > now }
        guard !days.isEmpty else { return "\(when). The day is here." }
        let labels = days.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let list = labels.count == 1 ? labels[0] : labels.dropLast().joined(separator: ", ") + " and " + labels[labels.count - 1]
        return "\(when). Back \(list)."
    }
}

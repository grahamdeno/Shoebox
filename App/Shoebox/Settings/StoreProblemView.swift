import SwiftUI

/// Shown instead of a crash when the store will not open. Nothing is deleted without a copy kept first.
struct StoreProblemView: View {
    var retry: () -> Void
    @State private var note = ""

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("Shoebox can't open your posts.")
                    .scaledFont(size: 34, weight: .bold)
                    .foregroundStyle(Theme.ink)
                Text("Nothing has been deleted.")
                    .scaledFont(size: 17)
                    .foregroundStyle(Theme.quiet)
                    .padding(.top, 12)
                Button("Try again") { retry() }
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundStyle(Theme.formAction)
                    .frame(minHeight: Metrics.touchMin, alignment: .leading)
                    .padding(.top, 28)
                Button("Start fresh, keep a copy") { startFresh() }
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundStyle(Theme.formAction)
                    .frame(minHeight: Metrics.touchMin, alignment: .leading)
                Text(note.isEmpty ? "A copy goes to Files, in Shoebox. Your daily backups there can bring posts back." : note)
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.quiet)
                    .padding(.top, 8)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func startFresh() {
        do {
            let folder = try Store.setAside()
            note = "Your old posts are in Files, Shoebox, \(folder.lastPathComponent)."
            retry()
        } catch {
            note = "Couldn't make a copy, so nothing was changed."
        }
    }
}

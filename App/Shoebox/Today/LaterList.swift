import SwiftUI

/// The Later list. Rises from the bottom bar on Today and on an opened post.
struct LaterList: View {
    let suggestion: LaterSuggestion
    let options: [LaterSuggestion]
    var onPick: (LaterSuggestion) -> Void
    var onPickDate: () -> Void
    var onLetGo: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bring it back")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.lidQuiet)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 8)

            Button { onPick(suggestion) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.label)
                        .font(.system(size: 19, weight: .semibold))
                    Text("Suggested, \(suggestion.reason)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.lidQuiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: Metrics.touchMin)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.lidSuggested
                            .shadow(.inner(color: Color(UIColor(hex: 0xB97A3A)).opacity(0.35), radius: 4, x: 2, y: 3))
                            .shadow(.inner(color: .white.opacity(0.7), radius: 3, x: -2, y: -2)))
                )
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            ForEach(options.filter { $0.label != suggestion.label }, id: \.label) { option in
                row(option.label) { onPick(option) }
            }
            row("Pick a date", action: onPickDate)

            Rectangle().fill(Theme.lidInk.opacity(0.14)).frame(height: 1)
                .padding(.horizontal, 28).padding(.top, 6)

            HStack {
                Button("Let go", action: onLetGo)
                    .foregroundStyle(Theme.lidQuiet)
                    .frame(minHeight: Metrics.touchMin)
                Spacer()
                Button("Close", action: onClose)
                    .fontWeight(.semibold)
                    .frame(minHeight: Metrics.touchMin)
            }
            .font(.system(size: 18))
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .foregroundStyle(Theme.lidInk)
        .frame(maxWidth: .infinity)
        .background(BarShape())
    }

    private func row(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

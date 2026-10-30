import SwiftUI

/// The box top as a button: sunflower with a slate lip, one word. The one colored control on screen.
struct LidButton: View {
    let title: String
    var width: CGFloat = 128
    var height: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Theme.lidLip.frame(height: 8)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.lidInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: width, height: height)
            .background(Theme.lid)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

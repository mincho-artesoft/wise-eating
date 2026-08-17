import SwiftData
import SwiftUI

struct PracticeFavoriteButton: View {
    let practice: Practice
    var font: Font = .title3
    var frameSize: CGFloat = 36
    var onToggle: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: practice.isFavorite ? "star.fill" : "star")
                .font(font)
                .foregroundStyle(Color.yellow)
                .frame(width: frameSize, height: frameSize)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            practice.isFavorite ? "Remove from Favorites" : "Add to Favorites"
        )
    }

    private func toggleFavorite() {
        let previousValue = practice.isFavorite
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            practice.isFavorite.toggle()
        }

        do {
            try modelContext.save()
            onToggle?()
        } catch {
            withAnimation {
                practice.isFavorite = previousValue
            }
            print("❌ Failed to save practice favorite: \(error.localizedDescription)")
        }
    }
}

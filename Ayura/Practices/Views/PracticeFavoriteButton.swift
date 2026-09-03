import SwiftData
import SwiftUI

struct PracticeFavoriteButton: View {
    let practice: Practice
    var font: Font = .title3
    var frameSize: CGFloat = 36
    var onToggle: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var catalogPreferences = CatalogPreferenceStore.shared

    var body: some View {
        let isFavorite = practice.effectiveIsFavorite
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(font)
                .foregroundStyle(Color.yellow)
                .frame(width: frameSize, height: frameSize)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            isFavorite ? "Remove from Favorites" : "Add to Favorites"
        )
        .animation(.spring(), value: catalogPreferences.revision)
    }

    private func toggleFavorite() {
        let previousValue = practice.effectiveIsFavorite

        do {
            try practice.setEffectiveFavorite(!previousValue, context: modelContext)
            onToggle?()
        } catch {
            print("❌ Failed to save practice favorite: \(error.localizedDescription)")
        }
    }
}

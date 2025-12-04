import SwiftUI

// MARK: - Non-sticky Nutrients section (no List header)
struct NutrientsSection<Collapsed: View, Expanded: View>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var showAll: Bool
    var onTurnedOn: () -> Void = {}
    @ViewBuilder let collapsed: () -> Collapsed
    @ViewBuilder let expanded:  () -> Expanded

    var body: some View {
        Group {
            // Title row (non-sticky)
            HStack {
                Text("Nutrients")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                Spacer()
                Button {
                    withAnimation(.easeInOut) {
                        let willTurnOn = !showAll
                        showAll.toggle()
                        if willTurnOn { onTurnedOn() }
                    }
                } label: {
                    Image(systemName: showAll ? "rectangle.split.3x1.fill" : "rectangle.split.3x3.fill")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .imageScale(.medium)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            // Content rows
            Group {
                if !showAll {
                    collapsed()
                } else {
                    expanded()
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, -30)
            .padding(.vertical, -16)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}

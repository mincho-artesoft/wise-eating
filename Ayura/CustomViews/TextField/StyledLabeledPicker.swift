import SwiftUI

struct StyledLabeledPicker<Content: View>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let label: String
    var height: CGFloat = 44
    var cornerRadius: CGFloat = 16
    var isFixedHeight: Bool = true
    var isRequired: Bool = false
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) { // Increased spacing
                Text(label)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                if isRequired {
                    Text("*")
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                }
            }
            .font(.caption)
            .padding(.leading, 4)

            content()
                .labelsHidden()
                .capsuleInput(
                    height: height,
                    cornerRadius: cornerRadius,
                    isFixedHeight: isFixedHeight
                )
        }
    }
}

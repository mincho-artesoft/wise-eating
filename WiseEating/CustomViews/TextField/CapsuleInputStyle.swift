import SwiftUI

// MARK: – CapsuleInputStyle
struct CapsuleInputStyle: ViewModifier {
    @ObservedObject private var effectManager = EffectManager.shared

    var height: CGFloat = 44 // Adjusted for better touch targets
    var cornerRadius: CGFloat = 16
    var isFixedHeight: Bool = true

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .frame(
                minHeight: height,
                maxHeight: isFixedHeight ? height : nil,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassCardStyle(cornerRadius: 20)
    }
}

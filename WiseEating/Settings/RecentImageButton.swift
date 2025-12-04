import SwiftUI

struct RecentImageButton: View {
    @ObservedObject private var effectManager = EffectManager.shared
    let image: UIImage
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                
                Circle()
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.1), lineWidth: 1)
            }
            .frame(width: 60, height: 60)
            .shadow(radius: 3, y: 2)
            .overlay(
                Group {
                    if isSelected {
                        Circle()
                            .stroke(effectManager.currentGlobalAccentColor, lineWidth: 4)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            )
            .frame(width: 68, height: 68)
            .scaleEffect(isSelected ? 1.1 : 1.0)

            Text("Recent")
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        }
    }
}

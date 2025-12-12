import SwiftUI

struct GalleryFoodItemCell: View {
    let item: FoodItem
    @ObservedObject private var effectManager = EffectManager.shared
    
    @State private var image: UIImage? = nil
    @State private var loadFailed: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if loadFailed {
                    Rectangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .overlay(Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.red.opacity(0.5)))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Rectangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .overlay(ProgressView().tint(effectManager.currentGlobalAccentColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .glassCardStyle(cornerRadius: 16)
            
            Text(item.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard image == nil && !loadFailed else { return }
        if let loadedImage = item.foodImage(variant: "144") {
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loadedImage
            }
        } else {
            self.loadFailed = true
        }
    }
}

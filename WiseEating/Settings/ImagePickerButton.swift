import SwiftUI

struct ImagePickerButton: View {
    @Binding var showingImagePicker: Bool
    @ObservedObject private var effectManager = EffectManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Circle()
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.1), lineWidth: 1)
            }
            .frame(width: 60, height: 60)
            .shadow(radius: 3, y: 2)
            .frame(width: 68, height: 68)

            Text("Add New")
                .font(.caption)
                .fontWeight(.medium)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingImagePicker = true
            }
        }
    }
}

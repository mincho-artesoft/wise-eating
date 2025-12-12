import SwiftUI

struct TestView: View {
    // State to track if the sheet is open
    @State private var showGallerySheet = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.orange)
            
            Text("Welcome to the App")
                .font(.headline)

            // Button to open the sheet
            Button("Open Food Gallery") {
                showGallerySheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .sheet(isPresented: $showGallerySheet) {
            VideoGalleryFoodSheet { selectedFood in
                print("Избрана храна: \(selectedFood.name)")
                // Тук запазете избраната храна във вашия модел
            }
        }
    }
}

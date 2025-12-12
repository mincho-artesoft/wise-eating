import SwiftUI



// Named exactly as requested: VideoGalleryFoodSheet
struct VideoGalleryFoodSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        // NavigationStack gives us the top bar for the title and Close button
        NavigationStack {
            List {
                // Mock items to look like a gallery
                ForEach(1...5, id: \.self) { index in
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 50)
                            
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Healthy Recipe #\(index)")
                                .fontWeight(.bold)
                            Text("Duration: 10:0\(index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Food Video Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Top-right Close button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

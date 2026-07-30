import SwiftUI


struct GlassBackgroundView: View {
    var cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .glassCardStyle(cornerRadius: cornerRadius)
    }
}

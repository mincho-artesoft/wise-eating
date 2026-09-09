import SwiftUI

struct ListMask: ViewModifier {
    let enabled: Bool
    let accent: Color
    func body(content: Content) -> some View {
        if enabled {
            content.mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: accent, location: 0.01),
                        .init(color: accent, location: 0.9),
                        .init(color: .clear, location: 0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            content
        }
    }
}

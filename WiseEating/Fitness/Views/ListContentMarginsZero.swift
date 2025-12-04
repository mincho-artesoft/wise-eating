import SwiftUI 
struct ListContentMarginsZero: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.contentMargins(.vertical, 0)
            } else {
                content
            }
        }
    }

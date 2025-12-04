import Combine
import SwiftUI

// MARK: - Нов клас за споделяне на състоянието на страницата
class PageState: ObservableObject {
    @Published var pageIndex: Int = 0
}

// MARK: - Изглед за точките-индикатори
struct PageIndicatorView: View {
    @ObservedObject var effectManager = EffectManager.shared

    let pageCount: Int
    @ObservedObject var pageState: PageState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(i == pageState.pageIndex ? effectManager.currentGlobalAccentColor
                          : effectManager.currentGlobalAccentColor.opacity(0.6))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity) // Центрира точките хоризонтално
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}


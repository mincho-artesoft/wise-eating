import SwiftUI
import AVFoundation
import SwiftData

// --- START OF CHANGE (1/4): Създаваме ObservableObject за управление на състоянието на всеки ред ---
@MainActor
class ScannedItem: ObservableObject, @preconcurrency Identifiable {
    let entity: DetectedObjectEntity
    var id: UUID { entity.id }

    @Published var isLoading: Bool = false
    @Published var productName: String?
    // --- START OF CHANGE ---
    @Published var resolvedFoodItem: FoodItem? = nil
    // --- END OF CHANGE ---

    init(entity: DetectedObjectEntity) {
        self.entity = entity
    }

    // --- НАЧАЛО НА ПРОМЯНАТА: Променен метод за поетапно обновяване на UI ---
    func performProductLookup(container: ModelContainer) {
        guard entity.category?.contains("GTIN") == true else { return }

        let gtin = self.entity.title

        Task {
            // 1. Задаваме първоначално състояние за зареждане на Main Actor.
            self.isLoading = true

            // 2. Извършваме бързото локално търсене.
            let modelContext = ModelContext(container)
            let productInfo = await ProductLookupService.shared.lookup(gtin: gtin)

            // 3. Актуализираме UI веднага след локалното търсене. Все още сме на Main Actor.
            self.productName = productInfo?.title
            
            // 4. Ако продукт е намерен локално, продължаваме с по-бавното AI търсене. В противен случай, приключваме.
            if let info = productInfo {
                // UI вече показва името на продукта със спинър.
                // Сега стартираме бавното AI търсене в отделна задача.
                let resolvedID: PersistentIdentifier? = try? await Task.detached(priority: .userInitiated) {
                    let smartFoodSearch = SmartFoodSearch(container: container)
                    let tokenizedWords = FoodItem.makeTokens(from: info.title)
                    let ids = await smartFoodSearch.searchFoodsAI(query: info.title, limit: 1, context: nil, requiredHeadwords: tokenizedWords)
                    return ids.first
                }.value

                // 5. Финална актуализация на UI на MainActor.
                if let pid = resolvedID {
                    let context = ModelContext(container)
                    if let foodItem = context.model(for: pid) as? FoodItem {
                        self.resolvedFoodItem = foodItem
                    }
                }
                self.isLoading = false
            } else {
                // Продуктът не е намерен локално, спираме зареждането.
                self.isLoading = false
            }
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА ---

}

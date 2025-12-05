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
            // ProductLookupService.shared.lookup се очаква да е thread-safe или actor-isolated
            let productInfo = await ProductLookupService.shared.lookup(gtin: gtin)

            // 3. Актуализираме UI веднага след локалното търсене.
            self.productName = productInfo?.title
            
            // 4. Ако продукт е намерен локално, продължаваме с AI търсенето.
            if let info = productInfo {
                // Инициализираме SmartFoodSearch3 (изисква MainActor)
                let smartFoodSearch = SmartFoodSearch3(container: container)
                let tokenizedWords = FoodItem.makeTokens(from: info.title)
                
                // Изпълняваме търсенето (SmartFoodSearch3.searchFoodsAI е async @MainActor)
                let ids = await smartFoodSearch.searchFoodsAI(
                    query: info.title,
                    limit: 1,
                    context: nil,
                    requiredHeadwords: tokenizedWords
                )

                // 5. Финална актуализация на UI на MainActor.
                if let pid = ids.first {
                    let context = ModelContext(container)
                    if let foodItem = context.model(for: pid) as? FoodItem {
                        self.resolvedFoodItem = foodItem
                    }
                }
            }
            
            // Приключваме зареждането
            self.isLoading = false
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
}

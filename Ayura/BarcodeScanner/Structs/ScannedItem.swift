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
    @Published var resolvedFoodItem: FoodItem? = nil
    @Published var mappingConfidence: Double?

    init(entity: DetectedObjectEntity) {
        self.entity = entity
    }

    // --- НАЧАЛО НА ПРОМЯНАТА: Променен метод за поетапно обновяване на UI ---
    func performProductLookup(container: ModelContainer) {
        guard entity.category?.contains("GTIN") == true else { return }

        let parsed = BarcodeParser.parse(self.entity.title)
        let gtin = parsed.extras["gtin"] ?? self.entity.title

        Task {
            self.isLoading = true
            self.resolvedFoodItem = nil
            self.mappingConfidence = nil
            defer { self.isLoading = false }

            let productInfo = await ProductLookupService.shared.lookup(gtin: gtin)
            self.productName = productInfo?.title

            if let info = productInfo {
                let smartFoodSearch = SmartFoodSearch3(container: container)
                if let match = await smartFoodSearch.searchFoodForBarcode(
                    productName: info.title
                ) {
                    self.resolvedFoodItem = match.food
                    self.mappingConfidence = match.confidence
                }
            }
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
}

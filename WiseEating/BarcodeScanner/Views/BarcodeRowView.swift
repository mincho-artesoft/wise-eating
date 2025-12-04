import SwiftUI

struct BarcodeRowView: View {
    @ObservedObject var item: ScannedItem
    @ObservedObject private var effectManager = EffectManager.shared
    
    var onSelect: () -> Void
    var onOpenURL: (URL) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // --- НАЧАЛО НА ПРОМЯНАТА: Добавяме ново първоначално състояние ---
            if !item.isLoading && item.productName == nil && item.resolvedFoodItem == nil && item.entity.category?.contains("GTIN") == true {
                // СЪСТОЯНИЕ 1: Кодът е засечен, но търсенето не е започнало. Показваме го веднага.
                VStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .frame(width: 30)

                VStack(alignment: .leading) {
                    Text("Scanned Barcode")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    Text(item.entity.title)
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else if item.isLoading {
            // --- КРАЙ НА ПРОМЯНАТА ---
                // SPINNER VIEW
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                }
                .frame(width: 30)
                
                // --- НАЧАЛО НА ПРОМЯНАТА: Показваме междинно състояние ---
                if let productName = item.productName {
                    // State: Product name was found, searching in local food database
                    VStack(alignment: .leading) {
                        Text(productName)
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Text("Searching in your local database…")
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // State: Initial lookup of the product name
                    VStack(alignment: .leading) {
                        Text("Looking up product…")
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Text(item.entity.title)
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // --- КРАЙ НА ПРОМЯНАТА ---

            } else if let foodItem = item.resolvedFoodItem {
                // --- START OF CHANGE: Remove button for resolved items ---
                VStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .frame(width: 30)

                VStack(alignment: .leading, spacing: 8) {
                    if let productName = item.productName {
                        Text(productName)
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }

                    FoodItemRowEventView(item: foodItem, amount: foodItem.referenceWeightG)
                }
                // --- END OF CHANGE ---
                
            } else {
                // CASE: Product not found in local database
                VStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    if let productName = item.productName {
                        // Found online, but NOT in local database
                        Text(productName)
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Text("Not found in your database")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        Text(item.entity.title)
                            .font(.caption2)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                            
                    } else if item.entity.category?.contains("GTIN") == true {
                        // Not found online nor locally
                        Text("Product with this code not found")
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Text(item.entity.title)
                            .font(.caption2)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    } else {
                        // Not a GTIN (e.g., QR code)
                        Text("Invalid Code")
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)

                        Text("The scanned code is not a valid product barcode.")
                            .font(.subheadline)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.default, value: item.isLoading)
        .animation(.default, value: item.resolvedFoodItem?.id)
    }
}

import SwiftUI

struct ConsumeStockViewContent: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let itemForDisplay: StorageItem
    let onConsume: (Double) -> Void
    let onCancel: () -> Void

    @State private var quantityToConsumeString: String
    private enum Field: Hashable { case quantity }
    @FocusState private var focusedField: Field?

    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var displayUnit: String { isImperial ? "oz" : "g" }
    
    private var maxAvailableInDisplayUnit: Double {
        isImperial ? UnitConversion.gToOz(itemForDisplay.totalQuantity) : itemForDisplay.totalQuantity
    }

    init(itemForDisplay: StorageItem, onConsume: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.itemForDisplay = itemForDisplay
        self.onConsume = onConsume
        self.onCancel = onCancel
        
        let isImperial = GlobalState.measurementSystem == "Imperial"
        let defaultGrams = 100.0
        let defaultOunces = 4.0
        
        let initialValueGrams = min(defaultGrams, itemForDisplay.totalQuantity)
        let initialValueOunces = min(defaultOunces, UnitConversion.gToOz(itemForDisplay.totalQuantity))
        
        let initialDisplayValue = isImperial ? initialValueOunces : initialValueGrams
        
        // 👉 уеднаквено с SelectedFoodRowView
        let formattedInitialValue = UnitConversion.formatDecimal(initialDisplayValue)
        self._quantityToConsumeString = State(initialValue: formattedInitialValue)
    }
    
    private var isFormValid: Bool {
        guard let quantityValue = GlobalState.double(from: quantityToConsumeString) else { return false }
        let quantityInGrams = isImperial ? UnitConversion.ozToG(quantityValue) : quantityValue
        return quantityInGrams > 0 && quantityInGrams <= itemForDisplay.totalQuantity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
             VStack(alignment: .leading, spacing: 16) {
                 let availableDisplay = UnitConversion.formatGramsToGramsOrOunces(itemForDisplay.totalQuantity)
                 Text("Available: \(availableDisplay.value) \(availableDisplay.unit)")
                     .font(.subheadline)
                     .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                     .padding(.leading, 20)
                     .padding(.top, 20)
                
                 Divider()
                     .background(effectManager.currentGlobalAccentColor.opacity(0.9))

                 HStack {
                     ConfigurableTextField(
                         title: "Quantity to consume",
                         value: $quantityToConsumeString,
                         type: .decimal,
                         focused: $focusedField,
                         fieldIdentifier: .quantity
                     )
                     .foregroundColor(effectManager.currentGlobalAccentColor)
                     
                     Text(displayUnit)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                 }
                 .padding(.horizontal, 20)
                 .padding(.bottom, 20)
             }
             .glassCardStyle(cornerRadius: 20)
             
            ZStack {
                Text("Consume")
                    .foregroundColor(isFormValid ? effectManager.currentGlobalAccentColor : effectManager.currentGlobalAccentColor.opacity(0.5))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .glassCardStyle(cornerRadius: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                if isFormValid {
                    guard let displayValue = GlobalState.double(from: quantityToConsumeString) else { return }
                    let gramsToConsume = isImperial ? UnitConversion.ozToG(displayValue) : displayValue
                    onConsume(gramsToConsume)
                    onCancel()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Consume")
            
            Spacer()
         }
        .padding()
        .onChange(of: quantityToConsumeString) { _, newStringValue in
            guard let enteredValue = GlobalState.double(from: newStringValue) else {
                return
            }

            if enteredValue > maxAvailableInDisplayUnit {
                let clampedValue = maxAvailableInDisplayUnit
                DispatchQueue.main.async {
                    self.quantityToConsumeString = UnitConversion.formatDecimal(clampedValue)
                }
            } else if enteredValue < 0 {
                 DispatchQueue.main.async {
                    self.quantityToConsumeString = UnitConversion.formatDecimal(0)
                }
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus == nil { formatInput() }
        }
        .onAppear {
            formatInput()
        }
    }
    
    private func formatInput() {
        if let value = GlobalState.double(from: quantityToConsumeString) {
            let nonNegativeValue = max(0, value)
            let clampedValue = min(nonNegativeValue, maxAvailableInDisplayUnit)
            quantityToConsumeString = UnitConversion.formatDecimal(clampedValue)
        } else if !quantityToConsumeString.isEmpty {
            quantityToConsumeString = UnitConversion.formatDecimal(0)
        }
    }
}

import SwiftUI

struct IngredientRowView<FocusField: Hashable>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Приемаме Binding директно към стойността в грамове
    @Binding var grams: Double
    let item: FoodItem
    
    // Генерични FocusState параметри
    @FocusState.Binding var focusedField: FocusField?
    let focusCase: FocusField
    
    var onDelete: () -> Void
    
    // --- NEW: Add maxValueInGrams ---
    let maxValueInGrams: Double?

    // Локално състояние само за текстовото поле
    @State private var textValue: String
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var ingredientUnit: String { isImperial ? "oz" : "g" }
    
    init(
        grams: Binding<Double>,
        item: FoodItem,
        focusedField: FocusState<FocusField?>.Binding,
        focusCase: FocusField,
        onDelete: @escaping () -> Void,
        maxValueInGrams: Double? = nil // <-- NEW
    ) {
        self._grams = grams
        self.item = item
        self._focusedField = focusedField
        self.focusCase = focusCase
        self.onDelete = onDelete
        self.maxValueInGrams = maxValueInGrams // <-- NEW
        
        let isImperialSystem = GlobalState.measurementSystem == "Imperial"
        let displayValue = isImperialSystem
            ? UnitConversion.gToOz_display(grams.wrappedValue)
            : grams.wrappedValue
        self._textValue = State(initialValue: UnitConversion.formatDecimal(displayValue))
    }

    var body: some View {
        HStack {
            if let thumbnail = item.foodImage(variant: "144") {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.15))
                    
                    Image(systemName: "fork.knife")
                        .font(.system(size: 20))
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                }
                .frame(width: 40, height: 40)
            }
            Text(item.name)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ConfigurableTextField(
                    title: ingredientUnit,
                    value: $textValue,
                    type: .decimal,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: $focusedField,
                    fieldIdentifier: focusCase
                )
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                Text(ingredientUnit)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .buttonStyle(.borderless)
                .tint(.red)
            }
        }
        .onChange(of: textValue) { _, newText in
            // Същото поведение като в SelectedFoodRowView.processChange
            if newText.isEmpty {
                grams = 0.0
                return
            }

            guard let displayValue = GlobalState.double(from: newText) else {
                return
            }

            var newGrams = isImperial ? UnitConversion.ozToG(displayValue) : displayValue

            // clamp по maxValueInGrams, ако има такава
            if let maxGrams = maxValueInGrams, newGrams > maxGrams {
                newGrams = maxGrams
                let clampedDisplayValue = isImperial
                    ? UnitConversion.gToOz_display(newGrams)
                    : newGrams
                DispatchQueue.main.async {
                    textValue = UnitConversion.formatDecimal(clampedDisplayValue)
                }
            }

            if abs(grams - newGrams) > 0.001 {
                grams = newGrams
            }
        }
        .onChange(of: grams) { _, newGrams in
            // Същата идея като updateTextFromModel
            let currentTextAsGrams: Double = {
                guard let displayValue = GlobalState.double(from: textValue) else { return 0 }
                return isImperial ? UnitConversion.ozToG(displayValue) : displayValue
            }()

            if abs(currentTextAsGrams - newGrams) > 0.001 {
                let displayValue = isImperial
                    ? UnitConversion.gToOz_display(newGrams)
                    : newGrams
                let newFormattedText = UnitConversion.formatDecimal(displayValue)
                if textValue != newFormattedText {
                    textValue = newFormattedText
                }
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            // Като formatTextFinal при loss of focus
            if newFocus != focusCase {
                let displayValue = isImperial
                    ? UnitConversion.gToOz_display(grams)
                    : grams
                let formatted = UnitConversion.formatDecimal(displayValue)
                if textValue != formatted {
                    textValue = formatted
                }
            }
        }
    }
}

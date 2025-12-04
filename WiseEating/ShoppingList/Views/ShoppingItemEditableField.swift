import SwiftUI

struct ShoppingItemEditableField: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // Външни зависимости
    @Binding var value: Double?
    let unit: String
    @FocusState.Binding var focusedField: ShoppingListDetailView.FocusableField?
    let focusCase: ShoppingListDetailView.FocusableField

    // Конфигурация
    var isInteger: Bool = false
    var maxValue: Double? = nil
    var usesUnitConversion: Bool = false
    var onFinalValue: ((Double?) -> Void)? // <--- НОВ ПАРАМЕТЪР

    // Вътрешно състояние
    @State private var text: String
    
    private var isFocused: Bool { focusedField == focusCase }
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }

    init(
        value: Binding<Double?>,
        unit: String,
        focusedField: FocusState<ShoppingListDetailView.FocusableField?>.Binding,
        focusCase: ShoppingListDetailView.FocusableField,
        isInteger: Bool = false,
        maxValue: Double? = nil,
        usesUnitConversion: Bool = false,
        onFinalValue: ((Double?) -> Void)? = nil // <--- НОВ ПАРАМЕТЪР
    ) {
        self._value = value
        self.unit = unit
        self._focusedField = focusedField
        self.focusCase = focusCase
        self.isInteger = isInteger
        self.maxValue = maxValue
        self.usesUnitConversion = usesUnitConversion
        self.onFinalValue = onFinalValue // <--- Инициализираме новия параметър

        var initialText = ""
        if let currentValueInGrams = value.wrappedValue {
            let isImperial = GlobalState.measurementSystem == "Imperial"
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (INIT) 👇 -----
            let displayValue = (usesUnitConversion && isImperial) ? UnitConversion.gToOz_display(currentValueInGrams) : currentValueInGrams
            // ----- 👆 КРАЙ НА ПРОМЯНАТА (INIT) 👆 -----
            
            if isInteger {
                initialText = String(Int(round(displayValue)))
            } else {
                initialText = GlobalState.decimalFormatter.string(from: NSNumber(value: displayValue)) ?? ""
            }
        }
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        HStack(spacing: 4) {
            ConfigurableTextField(
                title: isInteger ? "Qty" : "0.00",
                value: $text,
                type: isInteger ? .integer : .decimal,
                placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                focused: $focusedField,
                fieldIdentifier: focusCase
            )
            .multilineTextAlignment(.trailing)
            .font(.subheadline)
            
            Text(unit)
        }
        .onChange(of: text) { _, newText in
            processLiveTyping(newText: newText)
        }
        .onChange(of: value) { _, newValue in
            updateTextFromModel(newValue: newValue)
        }
        .onChange(of: isFocused) { _, isNowFocused in
            if !isNowFocused {
                formatTextFinal()
                // Извикваме callback-а, когато полето загуби фокус
                onFinalValue?(value) // <--- НОВО: Извикваме callback
            }
        }
    }

    private func processLiveTyping(newText: String) {
        if newText.isEmpty {
            if value != nil { value = nil }
            return
        }

        guard var parsedDisplayValue = GlobalState.double(from: newText) else { return }

        if let maxVal = maxValue {
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (PROCESS) 👇 -----
            // Използваме gToOz_display, за да гарантираме, че сравняваме ябълки с ябълки, ако се наложи.
            // Тук обаче е по-добре да сравняваме в display units директно.
            let maxInDisplayUnits = (usesUnitConversion && isImperial) ? UnitConversion.gToOz_display(maxVal) : maxVal
            // ----- 👆 КРАЙ НА ПРОМЯНАТА (PROCESS) 👆 -----
            if parsedDisplayValue > maxInDisplayUnits {
                parsedDisplayValue = maxInDisplayUnits
            }
        }

        let finalValueInGrams = (usesUnitConversion && isImperial) ? UnitConversion.ozToG(parsedDisplayValue) : parsedDisplayValue
        let finalValue = isInteger ? floor(finalValueInGrams) : finalValueInGrams
        
        if value != finalValue {
            value = finalValue
        }
    }

    private func formatTextFinal() {
        guard let currentValueInGrams = value else {
            if !text.isEmpty { text = "" }
            return
        }
        
        // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (FORMAT) 👇 -----
        let displayValue = (usesUnitConversion && isImperial) ? UnitConversion.gToOz_display(currentValueInGrams) : currentValueInGrams
        // ----- 👆 КРАЙ НА ПРОМЯНАТА (FORMAT) 👆 -----
        
        let formattedText = isInteger
            ? String(Int(round(displayValue)))
            : GlobalState.decimalFormatter.string(from: NSNumber(value: displayValue)) ?? ""

        if text != formattedText {
            text = formattedText
        }
    }
    
    private func updateTextFromModel(newValue: Double?) {
        let currentTextAsDouble = GlobalState.double(from: text)
        
        let displayValueFromModel: Double?
        if let grams = newValue {
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (UPDATE) 👇 -----
            displayValueFromModel = (usesUnitConversion && isImperial) ? UnitConversion.gToOz_display(grams) : grams
            // ----- 👆 КРАЙ НА ПРОМЯНАТА (UPDATE) 👆 -----
        } else {
            displayValueFromModel = nil
        }
        
        if currentTextAsDouble != displayValueFromModel {
            if let displayValue = displayValueFromModel {
                let formattedText = isInteger
                    ? String(Int(round(displayValue)))
                    : GlobalState.decimalFormatter.string(from: NSNumber(value: displayValue)) ?? ""
                if text != formattedText { text = formattedText }
            } else {
                if !text.isEmpty { text = "" }
            }
        }
    }
}

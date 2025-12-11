import SwiftUI

struct BatchCardView: View {
    @Bindable var batch: Batch
    var deleteAction: () -> Void
    var onQuantityChanged: (Double) -> Void
    @ObservedObject private var effectManager = EffectManager.shared

    // ----- 👇 НАЧАЛО НА ПРОМЯНА 1: Променяме maxQuantity на грамове -----
    private let maxQuantityGrams: Double = 30000.0
    // ----- 👆 КРАЙ НА ПРОМЯНА 1 -----

    @State private var quantityString: String
    @State private var hasExpiration: Bool
    @State private var oldValueInGrams: Double // Променяме името за яснота

    var focusedField: FocusState<Batch.ID?>.Binding
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 2: Добавяме helpers за мерни единици -----
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var displayUnit: String { isImperial ? "oz" : "g" }
    
    private var maxQuantityInDisplayUnit: Double {
        isImperial ? UnitConversion.gToOz(maxQuantityGrams) : maxQuantityGrams
    }
    // ----- 👆 КРАЙ НА ПРОМЯНА 2 -----

    init(batch: Batch,
         deleteAction: @escaping () -> Void,
         onQuantityChanged: @escaping (Double) -> Void,
         focusedField: FocusState<Batch.ID?>.Binding)
    {
        self.batch = batch
        self.deleteAction = deleteAction
        self.onQuantityChanged = onQuantityChanged
        self.focusedField = focusedField
        
        self._hasExpiration = State(initialValue: batch.expirationDate != nil)
        // Стойността, която пазим за сравнение, ВИНАГИ е в грамове
        self._oldValueInGrams = State(initialValue: batch.quantity)
        
        // ----- 👇 НАЧАЛО НА ПРОМЯНА 3: Коригираме инициализацията на quantityString -----
        let isImperial = GlobalState.measurementSystem == "Imperial"
        let displayValue = isImperial ? UnitConversion.gToOz(batch.quantity) : batch.quantity
        let initialQuantityString = UnitConversion.formatDecimal(displayValue)
        self._quantityString = State(initialValue: initialQuantityString)
        // ----- 👆 КРАЙ НА ПРОМЯНА 3 -----
    }

    private var isExpired: Bool {
        guard let expDate = batch.expirationDate else { return false }
        return Calendar.current.startOfDay(for: expDate) <= Calendar.current.startOfDay(for: Date())
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quantity")
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()
                
                // ----- 👇 НАЧАЛО НА ПРОМЯНА 4: Адаптираме TextField и мерната единица -----
                ConfigurableTextField(
                    title: displayUnit,
                    value: $quantityString,
                    type: .decimal, // Променяме на .decimal за унциите
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6)
                )
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .focused(focusedField, equals: batch.id)
                
                Text(displayUnit) // Показваме "oz" или "g"
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                // ----- 👆 КРАЙ НА ПРОМЯНА 4 -----
            }
            
            Toggle(isOn: $hasExpiration.animation()) {
                Text("Has Expiration Date")
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light)

            if hasExpiration {
                HStack {
                    Text("Expires on")
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    
                    Spacer()
                    
                    CustomDatePicker(
                        selection: Binding(
                            get: { batch.expirationDate ?? Date() },
                            set: { batch.expirationDate = $0 }
                        ),
                        tintColor: UIColor(effectManager.currentGlobalAccentColor),
                        textColor: UIColor(effectManager.currentGlobalAccentColor)
                    )
                    .frame(width: 120, height: 50)
                }
                .padding(.top, -10)
            }
            
            Divider()
                .background(effectManager.currentGlobalAccentColor.opacity(0.9))
            
            HStack {
                Spacer()
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete Batch", systemImage: "minus.circle")
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .buttonStyle(.borderless)
            }
        }
        
        .padding(20)
        .overlay {
            if isExpired {
                RoundedRectangle(cornerRadius: 20).stroke(.orange, lineWidth: 4)
            }
        }
        // ----- 👇 НАЧАЛО НА ПРОМЯНА 5: Обновяваме цялата логика в onChange -----
        .onChange(of: quantityString) { _, newStringValue in
            guard let newDisplayValue = GlobalState.double(from: newStringValue) else {
                if !newStringValue.isEmpty {
                    // Ако въведеното не е число, не правим нищо
                } else {
                    // Ако полето е изчистено
                    batch.quantity = 0
                    let difference = -oldValueInGrams
                    if difference != 0 {
                        onQuantityChanged(difference)
                    }
                    oldValueInGrams = 0
                }
                return
            }
            
            // Ограничаваме стойността спрямо максимума за показване
            let clampedDisplayValue = min(newDisplayValue, maxQuantityInDisplayUnit)
            
            // Конвертираме въведената (и евентуално ограничена) стойност обратно в грамове
            let newGramsValue = isImperial ? UnitConversion.ozToG(clampedDisplayValue) : clampedDisplayValue
            
            // Изчисляваме разликата в грамове
            let differenceInGrams = newGramsValue - oldValueInGrams
            
            // Извикваме callback-а с разликата в грамове
            if abs(differenceInGrams) > 0.01 {
                onQuantityChanged(differenceInGrams)
            }
            
            // Запазваме новата стойност в грамове в модела и за бъдещи сравнения
            batch.quantity = newGramsValue
            oldValueInGrams = newGramsValue
            
            // Ако сме ограничили стойността, обновяваме текстовото поле, за да го отрази
            if newDisplayValue > maxQuantityInDisplayUnit {
                DispatchQueue.main.async {
                    self.quantityString = UnitConversion.formatDecimal(clampedDisplayValue)
                }
            }
        }
        // ----- 👆 КРАЙ НА ПРОМЯНА 5 -----
        .onChange(of: focusedField.wrappedValue) { _, newFocus in
            if newFocus == nil {
                formatInput()
            }
        }
        .onChange(of: hasExpiration) { _, newValue in
            if !newValue {
                batch.expirationDate = nil
            } else if batch.expirationDate == nil {
                batch.expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
            }
        }
    }
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 6: Обновяваме formatInput -----
    private func formatInput() {
        let displayValue = isImperial ? UnitConversion.gToOz(batch.quantity) : batch.quantity
        quantityString = UnitConversion.formatDecimal(displayValue)
    }
    // ----- 👆 КРАЙ НА ПРОМЯНА 6 -----
}

import SwiftUI

struct BatchEditRow: View {
    @Binding var batch: EditableBatch
    @Binding var product: EditableProduct
    var focusedBatchID: FocusState<UUID?>.Binding
    let onDelete: () -> Void
    let onInteract: () -> Void
    @ObservedObject private var effectManager = EffectManager.shared

    // Максималното количество ВИНАГИ е в грамове
    private let maxQuantityGrams: Double = 30000.0
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 1: Добавяме helpers за мерни единици -----
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var displayUnit: String { isImperial ? "oz" : "g" }
    
    private var maxQuantityInDisplayUnit: Double {
        isImperial ? UnitConversion.gToOz(maxQuantityGrams) : maxQuantityGrams
    }
    // ----- 👆 КРАЙ НА ПРОМЯНА 1 -----
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quantity")
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()
                
                // ----- 👇 НАЧАЛО НА ПРОМЯНА 2: Адаптираме TextField и мерната единица -----
                ConfigurableTextField(
                    title: displayUnit,
                    value: $batch.quantityString,
                    type: .decimal, // Променяме на decimal за унции
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: focusedBatchID,
                    fieldIdentifier: batch.id,
                    onFocus: onInteract
                )
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.trailing)
                
                Text(displayUnit) // Показва "oz" или "g"
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                // ----- 👆 КРАЙ НА ПРОМЯНА 2 -----
            }
            
            Toggle(isOn: $batch.hasExpiration.animation()) {
                Text("Has Expiration Date")
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .onChange(of: batch.hasExpiration) { _, _ in
                onInteract()
            }

            if batch.hasExpiration {
                HStack {
                    Text("Expires on")
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    
                    Spacer()
                    
                    CustomDatePicker(
                        selection: $batch.expirationDate,
                        tintColor: UIColor(effectManager.currentGlobalAccentColor),
                        textColor: UIColor(effectManager.currentGlobalAccentColor)
                    )
                    .frame(width: 120, height: 50)
                    .onChange(of: batch.expirationDate) { _, _ in
                         onInteract()
                    }
                }
                .padding(.top, -10)
            }
            
            let visibleBatchesCount = product.batches.filter { !$0.isMarkedForDeletion }.count
            if visibleBatchesCount > 1 {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        onInteract()
                        onDelete()
                    } label: {
                        Label("Delete Batch", systemImage: "minus.circle")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        // ----- 👇 НАЧАЛО НА ПРОМЯНА 3: Обновяваме onChange логиката -----
        .onChange(of: batch.quantityString) { _, newText in
            // позволяваме празно по време на редакция
            if newText.isEmpty {
                return
            }
            
            guard let displayValue = GlobalState.double(from: newText) else {
                // невалиден вход – не пипаме нищо, за да не пречим на въвеждането
                return
            }

            // clamp в диапазона [0, maxQuantityInDisplayUnit]
            let clampedDisplayValue = min(max(displayValue, 0), maxQuantityInDisplayUnit)
            
            // ако сме го ограничили или просто искаме „чист“ формат – реформираме
            if abs(clampedDisplayValue - displayValue) > 0.0001 {
                DispatchQueue.main.async {
                    batch.quantityString = UnitConversion.formatDecimal(clampedDisplayValue)
                }
            }
        }
        // ----- 👆 КРАЙ НА ПРОМЯНА 3 -----
    }
}

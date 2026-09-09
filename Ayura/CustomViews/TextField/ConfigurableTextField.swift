import SwiftUI

/// Един универсален, преизползваем TextField, който може да бъде конфигуриран
/// да се държи като поле за стандартен, целочислен или десетичен вход.
struct ConfigurableTextField<Field: Hashable>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Configuration Enum
    enum FieldType {
        case standard
        case integer
        case decimal
    }

    // MARK: - Properties
    let title: String
    @Binding var value: String
    let type: FieldType
    let placeholderColor: Color?
    let textAlignment: TextAlignment // <-- NEW
    
    // Опционални параметри за интеграция с FocusState.
    var focused: FocusState<Field?>.Binding?
    var fieldIdentifier: Field?
    var onFocus: (() -> Void)?
   
    // MARK: - Body
    var body: some View {
        ZStack {
            // 1. Показваме нашия персонализиран плейсхолдър (Text) само ако стойността е празна.
            if value.isEmpty {
                Text(title)
                    .foregroundColor(placeholderColor ?? effectManager.currentGlobalAccentColor.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: textAlignment.horizontalAlignment, vertical: .center))
                    .allowsHitTesting(false)
            }

            // 2. Истинският TextField вече има празен плейсхолдър (""),
            // защото нашият Text го замества.
            let textField = TextField("", text: $value)
                .keyboardType(keyboardType)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(textAlignment) // <-- Align the actual text input
                .onChange(of: value, handleValidation)

            if let focused = focused, let fieldIdentifier = fieldIdentifier {
                textField
                    .focused(focused, equals: fieldIdentifier)
                    .onChange(of: focused.wrappedValue) { oldValue, newValue in
                        if newValue == fieldIdentifier {
                            onFocus?()
                        }
                    }
            } else {
                textField
            }
        }
    }

    // MARK: - Computed Properties
    private var keyboardType: UIKeyboardType {
        switch type {
        case .integer, .decimal:
            return .numbersAndPunctuation
        case .standard:
            return .default
        }
    }

    // MARK: - Private Methods
    private func handleValidation(oldValue: String, newValue: String) {
           switch type {
           case .standard:
               break
           case .integer:
               let filtered = newValue.filter { "0123456789".contains($0) }
               if filtered != newValue {
                   DispatchQueue.main.async {
                       value = filtered
                   }
               }
           case .decimal:
               if !GlobalState.isValidDecimal(newValue) {
                   DispatchQueue.main.async {
                       value = oldValue
                   }
               }
           }
       }
}

// MARK: - Custom Initializers
extension ConfigurableTextField {
    
    /// Инициализатор за полета, които ИЗПОЛЗВАТ FocusState.
    init(
        title: String,
        value: Binding<String>,
        type: FieldType,
        placeholderColor: Color? = nil,
        textAlignment: TextAlignment = .trailing,
        focused: FocusState<Field?>.Binding,
        fieldIdentifier: Field,
        onFocus: (() -> Void)? = nil
    ) {
        self.title = title
        self._value = value
        self.type = type
        self.placeholderColor = placeholderColor
        self.textAlignment = textAlignment // <-- NEW
        self.focused = focused
        self.fieldIdentifier = fieldIdentifier
        self.onFocus = onFocus
    }

    /// Инициализатор за полета, които НЕ ИЗПОЛЗВАТ FocusState.
    init(
        title: String,
        value: Binding<String>,
        type: FieldType,
        placeholderColor: Color? = nil,
        textAlignment: TextAlignment = .trailing
    ) where Field == Never {
        self.title = title
        self._value = value
        self.type = type
        self.placeholderColor = placeholderColor
        self.textAlignment = textAlignment
        self.focused = nil
        self.fieldIdentifier = nil
        self.onFocus = nil
    }
}


import SwiftUI

struct TrainingPlanExerciseRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    @Binding var link: TrainingPlanExercise
    @FocusState.Binding var focusedField: TrainingPlanEditorView.FocusableField?
    let focusCase: TrainingPlanEditorView.FocusableField
    var onDelete: () -> Void

    @State private var textValue: String
    @State private var isExpanded: Bool = false // За разгъване на сетовете

    private var item: ExerciseItem? { link.exercise }
    private var duration: Double { link.durationMinutes }
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var weightUnit: String { isImperial ? "lbs" : "kg" }
    
    // Picker Ranges
    private let repsRange = Array(0...999)
    private let weightWholeRange = Array(0...999)
    private let weightDecimalRange = Array(0...99)
    private let weightDecimalRangeImperial = Array(0...99)
    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    init(
        link: Binding<TrainingPlanExercise>,
        focusedField: FocusState<TrainingPlanEditorView.FocusableField?>.Binding,
        focusCase: TrainingPlanEditorView.FocusableField,
        onDelete: @escaping () -> Void
    ) {
        self._link = link
        self._focusedField = focusedField
        self.focusCase = focusCase
        self.onDelete = onDelete
        self._textValue = State(initialValue: String(format: "%.0f", link.wrappedValue.durationMinutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row (Exercise Name, Duration, Delete, Chevron)
            Button(action: {
                withAnimation { isExpanded.toggle() }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item?.name ?? "Unknown")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .font(.headline)
                            .lineLimit(2)
                        
                        Text("\(link.sets.count) sets planned")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    HStack(spacing: 4) {
                        ConfigurableTextField(
                            title: "min",
                            value: $textValue,
                            type: .integer,
                            placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                            focused: $focusedField,
                            fieldIdentifier: focusCase
                        )
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .foregroundStyle(effectManager.currentGlobalAccentColor)

                        Text("min")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .padding(.trailing, 8)
                    
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .padding(.trailing, 8)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded Section (Sets)
            if isExpanded {
                VStack(spacing: 8) {
                    Divider().padding(.vertical, 4)
                    
                    // List of Sets
                    ForEach($link.sets.sorted(by: { ($0.wrappedValue.id.uuidString) < ($1.wrappedValue.id.uuidString) })) { $set in
                        setRow(for: $set)
                    }
                    
                    // Add Set Button
                    Button(action: {
                       withAnimation {
                           let newSet = TrainingPlanSet(reps: 10, weight: 0)
                           link.sets.append(newSet)
                       }
                    }) {
                        HStack {
                            Spacer()
                            Text("Add Set")
                                .font(.caption.bold())
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                            Spacer()
                        }
                        .frame(height: 40) // <--- ПРОМЯНАТА Е ТУК (сложете 40, 44 или 50)
                        .glassCardStyle(cornerRadius: 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding(12)
        .glassCardStyle(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        
        .onChange(of: textValue) { _, newText in
            if let newDuration = Double(newText) {
                link.durationMinutes = newDuration
            } else if newText.isEmpty {
                link.durationMinutes = 0
            }
        }
        .onChange(of: link.durationMinutes) { _, newDuration in
            let currentTextAsDouble = Double(textValue) ?? 0.0
            if abs(currentTextAsDouble - newDuration) > 0.1 {
                textValue = String(format: "%.0f", newDuration)
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus != focusCase {
                let clampedDuration = max(1, min(link.durationMinutes, 999))
                textValue = String(format: "%.0f", clampedDuration)
                link.durationMinutes = clampedDuration
            }
        }
    }
    
    // MARK: - Set Row View
    private func setRow(for setBinding: Binding<TrainingPlanSet>) -> some View {
        let pickerColorScheme: ColorScheme = effectManager.isLightRowTextColor ? .dark : .light
        
        // Find index safely
        let setIndex = link.sets.firstIndex(where: { $0.id == setBinding.wrappedValue.id }) ?? 0

        return HStack(alignment: .center, spacing: 12) {
            // Label
            Text("Set \(setIndex + 1)")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .frame(width: 50, height: 80, alignment: .leading)

            // Reps
            VStack(spacing: 4) {
                Text("Repetitions")
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .frame(width: 80, alignment: .center)

                Picker("Reps", selection: repsBinding(for: setBinding)) {
                    ForEach(repsRange, id: \.self) { rep in
                        Text("\(rep)").tag(rep)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 80, height: 80)
                .clipped()
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, pickerColorScheme)
                .offset(y: -7)
            }

            // Weight
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Text("Weight")
                    Text(weightUnit)
                }
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .frame(width: 158, alignment: .center)

                HStack(spacing: 0) {
                    Picker("Weight Whole", selection: weightWholeBinding(for: setBinding)) {
                        ForEach(weightWholeRange, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 80)
                    .clipped()

                    Text(decimalSeparator)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .frame(width: 18, alignment: .center)

                    Picker("Weight Decimal", selection: weightDecimalBinding(for: setBinding)) {
                        ForEach(weightDecimalRange, id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 60, height: 80)
                    .clipped()
                }
                .offset(y: -7)
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, pickerColorScheme)
            }

            Spacer(minLength: 0)

            // Delete Set
            Button(action: {
                withAnimation {
                    // SwiftData delete is implicit when removed from array if cascade is set,
                    // but cleaner to be explicit if possible or just rely on array manipulation
                    // Since it's binding, we manipulate parent's array
                    link.sets.removeAll { $0.id == setBinding.wrappedValue.id }
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(6)
        .glassCardStyle(cornerRadius: 10)
    }
    
    // Bindings Logic (Copied from LogView but adapted for TrainingPlanSet)
    private func repsBinding(for setBinding: Binding<TrainingPlanSet>) -> Binding<Int> {
        Binding<Int>(
            get: { setBinding.wrappedValue.reps ?? 0 },
            set: { newValue in setBinding.wrappedValue.reps = (newValue > 0) ? newValue : nil }
        )
    }

    private func currentWeightParts(for set: TrainingPlanSet) -> (whole: Int, dec: Int) {
        let rawValue = set.weight ?? 0.0
        let displayValue = isImperial ? UnitConversion.kgToLbs(rawValue) : rawValue
        let scaled = (displayValue * 100).rounded()
        let intScaled = Int(scaled)
        return (intScaled / 100, intScaled % 100)
    }

    private var decimalDivisor: Double { 100.0 }

    private func weightWholeBinding(for setBinding: Binding<TrainingPlanSet>) -> Binding<Int> {
        Binding<Int>(
            get: { currentWeightParts(for: setBinding.wrappedValue).whole },
            set: { newWhole in
                let parts = currentWeightParts(for: setBinding.wrappedValue)
                let displayValue = Double(newWhole) + (Double(parts.dec) / decimalDivisor)
                let weightInKg = isImperial ? UnitConversion.lbsToKg(displayValue) : displayValue
                setBinding.wrappedValue.weight = (weightInKg > 0) ? weightInKg : nil
            }
        )
    }

    private func weightDecimalBinding(for setBinding: Binding<TrainingPlanSet>) -> Binding<Int> {
        Binding<Int>(
            get: { currentWeightParts(for: setBinding.wrappedValue).dec },
            set: { newDec in
                let parts = currentWeightParts(for: setBinding.wrappedValue)
                let displayValue = Double(parts.whole) + (Double(newDec) / decimalDivisor)
                let weightInKg = isImperial ? UnitConversion.lbsToKg(displayValue) : displayValue
                setBinding.wrappedValue.weight = (weightInKg > 0) ? weightInKg : nil
            }
        )
    }
}

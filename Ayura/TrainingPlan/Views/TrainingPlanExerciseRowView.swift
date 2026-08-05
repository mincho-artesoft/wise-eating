import SwiftUI

struct TrainingPlanExerciseRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    @Binding var link: TrainingPlanExercise
    @FocusState.Binding var focusedField: TrainingPlanEditorView.FocusableField?
    let focusCase: TrainingPlanEditorView.FocusableField
    var onDelete: () -> Void

    @State private var textValue: String
    @State private var isExpanded: Bool = false

    private var item: ExerciseItem? { link.exercise }
    private var duration: Double { link.durationSeconds }
    
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
        self._textValue = State(initialValue: String(format: "%.0f", link.wrappedValue.durationSeconds))
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
                            .multilineTextAlignment(.leading)
                        
                        Text("\(link.sets.count) sets planned")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        ConfigurableTextField(
                            title: "sec",
                            value: $textValue,
                            type: .integer,
                            placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                            focused: $focusedField,
                            fieldIdentifier: focusCase
                        )
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .foregroundStyle(effectManager.currentGlobalAccentColor)

                        Text("sec")
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
                    
                    let sortedSets = link.sets.sorted { $0.orderIndex < $1.orderIndex }
                    
                    ForEach(sortedSets) { set in
                        if let index = link.sets.firstIndex(where: { $0.id == set.id }) {
                            setRow(for: $link.sets[index])
                                .id(set.id)
                        }
                    }
                    
                    Button(action: {
                       withAnimation {
                           let nextIndex = link.sets.count
                           let newSet = TrainingPlanSet(reps: 10, weight: 0, orderIndex: nextIndex)
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
                        .frame(height: 40)
                        .glassCardStyle(cornerRadius: 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .glassCardStyle(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        
        .onChange(of: textValue) { _, newText in
            if let newDuration = Double(newText) {
                link.durationSeconds = newDuration
            } else if newText.isEmpty {
                link.durationSeconds = 0
            }
        }
        .onChange(of: link.durationSeconds) { _, newDuration in
            let currentTextAsDouble = Double(textValue) ?? 0.0
            if abs(currentTextAsDouble - newDuration) > 0.1 {
                textValue = String(format: "%.0f", newDuration)
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus != focusCase {
                let clampedDuration = max(1, min(link.durationSeconds, 86_400))
                textValue = String(format: "%.0f", clampedDuration)
                link.durationSeconds = clampedDuration
            }
        }
    }
    
    // MARK: - Set Row View
    // MARK: - Set Row View
        private func setRow(for setBinding: Binding<TrainingPlanSet>) -> some View {
                let pickerColorScheme: ColorScheme = effectManager.appColorScheme
                let displayIndex = setBinding.wrappedValue.orderIndex + 1

                return VStack(spacing: 6) {
                    // 🔹 ПЪРВИ РЕД
                    HStack(alignment: .center, spacing: 8) {
                        // Label
                        Text("Set \(displayIndex)")
                            .font(.subheadline)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .frame(width: 45, height: 80, alignment: .leading)

                        // Reps OR Failure OR Time
                        VStack(spacing: 4) {
                            // ✅ ДИНАМИЧЕН ЕТИКЕТ: Sec / Min / Reps
                            let unitLabel: String = {
                                if setBinding.wrappedValue.isTimeBased {
                                    return setBinding.wrappedValue.timeUnit == .minutes ? "Min" : "Sec"
                                }
                                return "Reps"
                            }()
                            
                            Text(unitLabel)
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .frame(width: 75, alignment: .center)

                            if setBinding.wrappedValue.isToFailure {
                                VStack {
                                    Spacer()
                                    Text("To Failure")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.orange)
                                        .multilineTextAlignment(.center)
                                        .padding(4)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(6)
                                    Spacer()
                                }
                                .frame(width: 75, height: 80)
                                .offset(y: -7)
                            } else {
                                Picker(unitLabel, selection: repsBinding(for: setBinding)) {
                                    ForEach(repsRange, id: \.self) { rep in
                                        Text("\(rep)").tag(rep)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 75, height: 80)
                                .clipped()
                                .tint(effectManager.currentGlobalAccentColor)
                                .environment(\.colorScheme, pickerColorScheme)
                                .offset(y: -7)
                            }
                        }

                        // Weight
                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Text("Weight")
                                Text(weightUnit)
                            }
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .frame(width: 140, alignment: .center)

                            HStack(spacing: 0) {
                                Picker("Weight Whole", selection: weightWholeBinding(for: setBinding)) {
                                    ForEach(weightWholeRange, id: \.self) { value in
                                        Text("\(value)").tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 70, height: 80)
                                .clipped()

                                Text(decimalSeparator)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    .frame(width: 10, alignment: .center)

                                Picker("Weight Decimal", selection: weightDecimalBinding(for: setBinding)) {
                                    ForEach(weightDecimalRange, id: \.self) { value in
                                        Text(String(format: "%02d", value)).tag(value)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 50, height: 80)
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
                                let idToDelete = setBinding.wrappedValue.id
                                link.sets.removeAll { $0.id == idToDelete }
                                let sorted = link.sets.sorted { $0.orderIndex < $1.orderIndex }
                                for (newIndex, set) in sorted.enumerated() {
                                    set.orderIndex = newIndex
                                }
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    // 🔹 ВТОРИ РЕД: Toggles
                    VStack(spacing: 0) {
                        HStack {
                            Text("To Failure")
                                .font(.subheadline)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                            
                            Spacer()
                            
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { setBinding.wrappedValue.isToFailure },
                                    set: { newValue in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            setBinding.wrappedValue.isToFailure = newValue
                                            if newValue {
                                                setBinding.wrappedValue.reps = nil
                                            }
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .environment(\.colorScheme, effectManager.appColorScheme)
                        }
                        .padding(.vertical, 8)
                        
                        Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        
                        // ✅ Time Based Toggle + Picker
                        HStack {
                            Text("Time Based")
                                .font(.subheadline)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                            
                            // ПИКЪР ЗА СЕКУНДИ/МИНУТИ
                            if setBinding.wrappedValue.isTimeBased {
                                Picker("", selection: setBinding.timeUnit) {
                                    Text("Sec").tag(TimeUnit.seconds)
                                    Text("Min").tag(TimeUnit.minutes)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .fixedSize()
                                .padding(.leading, 8)
                                .environment(\.colorScheme, effectManager.appColorScheme)
                            }
                            
                            Spacer()
                            
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { setBinding.wrappedValue.isTimeBased },
                                    set: { newValue in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            setBinding.wrappedValue.isTimeBased = newValue
                                            if newValue {
                                                // Default на 1 ако е празно
                                                if setBinding.wrappedValue.reps == nil && !setBinding.wrappedValue.isToFailure {
                                                    setBinding.wrappedValue.reps = 1
                                                }
                                            }
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .environment(\.colorScheme, effectManager.appColorScheme)
                        }
                        .padding(.vertical, 8)
                    }

                }
                .padding(6)
                .glassCardStyle(cornerRadius: 10)
            }
    
    // Bindings Logic (непроменена)
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

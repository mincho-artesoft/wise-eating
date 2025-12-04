import SwiftUI

struct ExerciseLogEntryView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Input
    let exercise: ExerciseItem
    let profile: Profile
    let onExpand: () -> Void
    
    // MARK: - Bindings
    @Binding var exerciseLog: ExerciseLog
    @Binding var isExpanded: Bool
    
    // MARK: - Focus State
    struct FocusField: Hashable {
        let exerciseID: Int
        let setID: UUID
    }
    @FocusState.Binding var focusedField: FocusField?
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var weightUnit: String { isImperial ? "lbs" : "kg" }
    
    // MARK: - Picker Ranges
    // --- НАЧАЛО НА ПРОМЯНАТА ---
    private let repsRange = Array(0...999)
    private let weightWholeRange = Array(0...999)
    private let weightDecimalRange = Array(0...99)
    private let weightDecimalRangeImperial = Array(0...99) // За два знака
    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }
    // --- КРАЙ НА ПРОМЯНАТА ---

    var body: some View {
        VStack(spacing: 0) {
            header
            
            if isExpanded {
                setsList
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    private var header: some View {
        Button(action: {
            if !isExpanded {
                onExpand()
            }
            withAnimation { isExpanded.toggle() }
        }) {
            HStack {
                exerciseImage
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    
                    Text("\(exerciseLog.sets.count) sets")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .contentShape(Rectangle()) // <-- ДОБАВЕТЕ ТОЗИ РЕД
        }
        .buttonStyle(.plain)
    }
    private var addSetRow: some View {
        HStack {
            Spacer()
            Text("Add Set")
                .font(.caption.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            Spacer()
        }
        .padding()
        .glassCardStyle(cornerRadius: 15)
        .padding(.top, 4)
        .contentShape(Rectangle())              // цялата карта е hit-area
        .onTapGesture {
            withAnimation {
                exerciseLog.sets.append(WorkoutSet(reps: nil, weight: nil))
            }
        }
        .accessibilityAddTraits(.isButton)       // за VoiceOver – да се държи като бутон
    }

    private var setsList: some View {
        VStack(spacing: 8) {
            Divider().padding(.vertical, 4)

            ForEach($exerciseLog.sets) { $set in
                setRow(for: $set)
            }

            addSetRow
        }

    }
    
    private func setRow(for setBinding: Binding<WorkoutSet>) -> some View {
        let set = setBinding.wrappedValue
        let setIndex = exerciseLog.sets.firstIndex(where: { $0.id == set.id }) ?? 0
        let pickerColorScheme: ColorScheme = effectManager.isLightRowTextColor ? .dark : .light

        return HStack(alignment: .center, spacing: 12) {          // центриране по вертикала
            // MARK: - Set label
            Text("Set \(setIndex + 1)")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .frame(width: 50, height: 80, alignment: .leading) // същата височина като picker-ите

            // MARK: - Reps колонка
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

            // MARK: - Weight колонка
            VStack(spacing: 4) {
                // Обща ширина = 80 (whole) + 18 (точка) + 60 (decimal) = 158
                HStack(spacing: 2) {
                    Text("Weight")
                    Text(weightUnit)
                }
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .frame(width: 158, alignment: .center)   // <- центрирано над трите колелца

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
                        if isImperial {
                            ForEach(weightDecimalRangeImperial, id: \.self) { value in
                                Text(String(format: "%02d", value)).tag(value)
                            }
                        } else {
                            ForEach(weightDecimalRange, id: \.self) { value in
                                Text(String(format: "%02d", value)).tag(value)
                            }
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

            // MARK: - Delete бутон
            Button(action: {
                withAnimation {
                    exerciseLog.sets.removeAll { $0.id == set.id }
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



    private func repsBinding(for setBinding: Binding<WorkoutSet>) -> Binding<Int> {
        Binding<Int>(
            get: {
                setBinding.wrappedValue.reps ?? 0
            },
            set: { newValue in
                setBinding.wrappedValue.reps = (newValue > 0) ? newValue : nil
            }
        )
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА: Актуализирани binding функции за тежест ---
    private func currentWeightParts(for set: WorkoutSet) -> (whole: Int, dec: Int) {
        let rawValue = set.weight ?? 0.0
        let displayValue = isImperial ? UnitConversion.kgToLbs(rawValue) : rawValue
        
        // Винаги работим с две десетични места
        let scaled = (displayValue * 100).rounded()        // 1.12 -> 112
        let intScaled = Int(scaled)
        
        let whole = intScaled / 100                        // 112 / 100 = 1
        let dec = intScaled % 100                          // 112 % 100 = 12
        
        return (whole, dec)
    }

    private var decimalDivisor: Double { 100.0 } // две десетични места за kg и lbs

    private func weightWholeBinding(for setBinding: Binding<WorkoutSet>) -> Binding<Int> {
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

    
    private func weightDecimalBinding(for setBinding: Binding<WorkoutSet>) -> Binding<Int> {
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


    @ViewBuilder
    private var exerciseImage: some View {
        if let photoData = exercise.photo, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage).resizable().scaledToFill().clipShape(Circle())
        } else if let assetName = exercise.assetImageName, let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage).resizable().scaledToFill().clipShape(Circle())
        } else {
            Image(systemName: "dumbbell.fill").resizable().scaledToFit().padding(10)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

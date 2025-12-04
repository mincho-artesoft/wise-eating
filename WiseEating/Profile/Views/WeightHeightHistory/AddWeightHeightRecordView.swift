import SwiftUI
import SwiftData

struct AddWeightHeightRecordView: View {
    // ... (всички properties остават същите) ...
    // MARK: - Required Properties
    let profile: Profile
    @Bindable var record: WeightHeightRecord
    let isNew: Bool
    
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State
    @State private var date: Date
    @State private var weight: String
    @State private var height: String
    @State private var headCircumference: String
    @State private var customMetrics: [String: String]
    @State private var isAddingNewMetric = false
    @State private var newMetricName = ""
    @State private var newMetricValue = ""

    // MARK: - Focus State
    private enum Field: Hashable {
        case weight, height, headCircumference, custom(String), newMetricValue, newMetricName
    }
    
    @FocusState private var focusedField: Field?
    
    // MARK: - Computed Properties & Constants
    private let maxValueMetric: Double = 500.0
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var weightUnit: String { isImperial ? "lbs" : "kg" }
    private var heightUnit: String { isImperial ? "in" : "cm" }
    private var ageInMonthsAtRecordDate: Int {
        Calendar.current.dateComponents([.month], from: profile.birthday, to: date).month ?? 0
    }
    private var displayMaxWeight: Double { isImperial ? UnitConversion.kgToLbs(maxValueMetric) : maxValueMetric }
    private var displayMaxHeight: Double { isImperial ? UnitConversion.cmToInches(maxValueMetric) : maxValueMetric }
    private var displayMaxCustomMetric: Double { maxValueMetric }
    private var navigationTitle: String { isNew ? "Add New Record" : "Edit Record" }

    private var allCustomMetricKeys: [String] {
        let historyKeys = profile.weightHeightHistory.flatMap { $0.customMetrics.keys }
        let allKeys = Set(historyKeys).union(customMetrics.keys)
        return Array(allKeys).sorted()
    }

    // MARK: - Init
    init(profile: Profile, record: WeightHeightRecord, isNew: Bool) {
        self.profile = profile
        self.record = record
        self.isNew = isNew

        _date = State(initialValue: record.date)
        
        _weight = State(initialValue: GlobalState.measurementSystem == "Imperial"
                           ? UnitConversion.formatDecimal(UnitConversion.kgToLbs(record.weight))
                           : UnitConversion.formatDecimal(record.weight))
        
        _height = State(initialValue: GlobalState.measurementSystem == "Imperial"
                           ? UnitConversion.formatDecimal(UnitConversion.cmToInches(record.height))
                           : UnitConversion.formatDecimal(record.height))
        
        _headCircumference = State(initialValue: {
            if let hc = record.headCircumference {
                return GlobalState.measurementSystem == "Imperial"
                       ? UnitConversion.formatDecimal(UnitConversion.cmToInches(hc))
                       : UnitConversion.formatDecimal(hc)
            }
            return ""
        }())

        _customMetrics = State(initialValue: record.customMetrics.mapValues { UnitConversion.formatDecimal($0) })
    }

    // MARK: - Body
    var body: some View {
        let dateBinding = Binding<Date>(
            get: { self.date },
            set: { newDate in
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: newDate)
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: self.date)
                
                var combinedComponents = dateComponents
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                combinedComponents.second = timeComponents.second
                
                if let combinedDate = calendar.date(from: combinedComponents),
                   combinedDate <= Date(),
                   combinedDate >= profile.birthday {
                    self.date = combinedDate
                }
            }
        )
        
        let timeBinding = Binding<Date>(
            get: { self.date },
            set: { newTime in
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: newTime)
                let dateComponents = calendar.dateComponents([.year, .month, .day, .second], from: self.date)
                
                var combinedComponents = dateComponents
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                
                if let combinedDate = calendar.date(from: combinedComponents), combinedDate <= Date() {
                    self.date = combinedDate
                }
            }
        )
        
        return ZStack(alignment: .topLeading) {
            ThemeBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 25) {
                            HStack {
                                Text("Date")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                Spacer()
                                
                                CustomDatePicker(
                                    selection: dateBinding,
                                    tintColor: UIColor(effectManager.currentGlobalAccentColor),
                                    textColor: .label,
                                    minimumDate: profile.birthday,
                                    maximumDate: Date()
                                )
                                .frame(height: 40)
                                
                                CustomTimePicker(
                                    selection: timeBinding,
                                    textColor: .label,
                                    maximumDate: Calendar.current.isDateInToday(date) ? Date() : nil
                                )
                                .frame(height: 40)
                            }

                            rowFor(title: "Weight", unit: weightUnit, value: $weight, validation: validationMessage(for: weight, maxValue: displayMaxWeight), fieldType: .decimal, fieldIdentifier: .weight)
                            
                            rowFor(title: "Height", unit: heightUnit, value: $height, validation: validationMessage(for: height, maxValue: displayMaxHeight), fieldType: .decimal, fieldIdentifier: .height)
                            
                            if ageInMonthsAtRecordDate <= 24 {
                                rowFor(title: "Head Circ.", unit: heightUnit, value: $headCircumference, validation: validationMessage(for: headCircumference, maxValue: displayMaxHeight), fieldType: .decimal, fieldIdentifier: .headCircumference)
                            }
                            
                            ForEach(allCustomMetricKeys, id: \.self) { key in
                                rowFor(title: key.capitalized, unit: "", value: bindingForCustomMetric(key: key), validation: validationMessage(for: customMetrics[key, default: ""], maxValue: displayMaxCustomMetric), fieldType: .decimal, fieldIdentifier: .custom(key))
                            }
                        }
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                        .padding()
                        
                        HStack {
                            addNewMetricSection
                        }
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                        .padding()
                    }
                    // --- НАЧАЛО НА ПРОМЯНАТА (2/5): Добавяме onChange за FocusState ---
                    .onChange(of: focusedField) { _, newFocus in
                        if newFocus == nil {
                            formatAllInputs()
                        } else {
                            guard let fieldID = newFocus else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(fieldID, anchor: .top)
                                }
                            }
                        }
                    }
                    // --- КРАЙ НА ПРОМЯНАТА (2/5) ---
                } // --- КРАЙ НА ПРОМЯНАТА (1/5): Край на ScrollViewReader
            }
        }
        .navigationBarHidden(true)
        .onChange(of: weight) { _, newStringValue in
            guard let numericValue = UnitConversion.parseDecimal(newStringValue) else { return }
            let convertedValue = isImperial ? UnitConversion.lbsToKg(numericValue) : numericValue
            if convertedValue > maxValueMetric {
                let clampedValue = isImperial ? UnitConversion.kgToLbs(maxValueMetric) : maxValueMetric
                DispatchQueue.main.async { self.weight = UnitConversion.formatDecimal(clampedValue) }
            }
        }
        .onChange(of: height) { _, newStringValue in
            guard let numericValue = UnitConversion.parseDecimal(newStringValue) else { return }
            let convertedValue = isImperial ? UnitConversion.inchesToCm(numericValue) : numericValue
            if convertedValue > maxValueMetric {
                let clampedValue = isImperial ? UnitConversion.cmToInches(maxValueMetric) : maxValueMetric
                DispatchQueue.main.async { self.height = UnitConversion.formatDecimal(clampedValue) }
            }
        }
        .onChange(of: headCircumference) { _, newStringValue in
            guard let numericValue = UnitConversion.parseDecimal(newStringValue) else { return }
            let convertedValue = isImperial ? UnitConversion.inchesToCm(numericValue) : numericValue
            if convertedValue > maxValueMetric {
                let clampedValue = isImperial ? UnitConversion.cmToInches(maxValueMetric) : maxValueMetric
                DispatchQueue.main.async { self.headCircumference = UnitConversion.formatDecimal(clampedValue) }
            }
        }
        .onChange(of: newMetricValue) { _, newStringValue in
            guard let numericValue = UnitConversion.parseDecimal(newStringValue) else { return }
            if numericValue > maxValueMetric {
                DispatchQueue.main.async { self.newMetricValue = UnitConversion.formatDecimal(maxValueMetric) }
            }
        }
    }

    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            Button("Cancel", action: { dismiss() })
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text(navigationTitle).font(.headline)
            Spacer()
            
            Button("Save", action: saveRecord)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.top, 10)
    }
    
    @ViewBuilder
    private func rowFor(title: String, unit: String, value: Binding<String>, validation: some View, fieldType: ConfigurableTextField<Field>.FieldType, fieldIdentifier: Field) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                ConfigurableTextField<Field>(
                    title: "Enter \(title.lowercased())",
                    value: value,
                    type: fieldType,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: $focusedField,
                    fieldIdentifier: fieldIdentifier
                )
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.trailing)
                
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
            validation
        }
        // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Добавяме ID на контейнера ---
        .id(fieldIdentifier)
        // --- КРАЙ НА ПРОМЯНАТА (3/5) ---
    }

    @ViewBuilder
    private var addNewMetricSection: some View {
        if isAddingNewMetric {
            VStack(alignment: .leading, spacing: 15) {
                ConfigurableTextField<Field>(
                    title: "Metric Name",
                    value: $newMetricName,
                    type: .standard,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .newMetricName,
                )
                // --- НАЧАЛО НА ПРОМЯНАТА (4/5): Добавяме ID и тук ---
                .id(Field.newMetricName)
                // --- КРАЙ НА ПРОМЯНАТА (4/5) ---
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .autocapitalization(.words)

                ConfigurableTextField<Field>(
                    title: "Value",
                    value: $newMetricValue,
                    type: .decimal,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .newMetricValue
                )
                // --- НАЧАЛО НА ПРОМЯНАТА (5/5): Добавяме ID и тук ---
                .id(Field.newMetricValue)
                // --- КРАЙ НА ПРОМЯНАТА (5/5) ---
                .foregroundColor(effectManager.currentGlobalAccentColor)
                
                validationMessage(for: newMetricValue, maxValue: displayMaxCustomMetric)
                
                HStack {
                    Button("Cancel", role: .destructive) {
                        withAnimation {
                            isAddingNewMetric = false
                            newMetricName = ""
                            newMetricValue = ""
                            focusedField = nil
                        }
                    }
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    Spacer()

                    Button("Add Metric") {
                        commitNewMetric()
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        newMetricName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        UnitConversion.parseDecimal(newMetricValue) == nil ||
                        (UnitConversion.parseDecimal(newMetricValue) ?? 0 > maxValueMetric)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .padding(.top, 10)
            }

        } else {
            Button {
                withAnimation {
                    isAddingNewMetric = true
                    focusedField = .newMetricName
                }
            } label: {
                HStack {
                     Spacer()
                     Label("Add New Metric", systemImage: "plus")
                         .foregroundStyle(effectManager.currentGlobalAccentColor)
                     Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // ... (останалите методи остават същите) ...
    @ViewBuilder
    private func validationMessage(for value: String, maxValue: Double) -> some View {
        if !value.isEmpty, let numericValue = UnitConversion.parseDecimal(value), numericValue > maxValue {
            Text("Value must not exceed \(UnitConversion.formatDecimal(maxValue)).")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
    
    private func bindingForCustomMetric(key: String) -> Binding<String> {
        Binding(
            get: { customMetrics[key, default: ""] },
            set: { newStringValue in
                guard let numericValue = UnitConversion.parseDecimal(newStringValue) else {
                    customMetrics[key] = newStringValue
                    return
                }
                
                if numericValue > maxValueMetric {
                    customMetrics[key] = UnitConversion.formatDecimal(maxValueMetric)
                } else {
                    customMetrics[key] = newStringValue
                }
            }
        )
    }

    private func commitNewMetric() {
        formatAllInputs()
        let trimmedName = newMetricName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let value = UnitConversion.parseDecimal(newMetricValue), value <= maxValueMetric else { return }
        
        withAnimation {
            customMetrics[trimmedName] = newMetricValue
            newMetricName = ""
            newMetricValue = ""
            isAddingNewMetric = false
            focusedField = nil
        }
    }
    
    private func formatAllInputs() {
        let currentWeightDisplay = UnitConversion.parseDecimal(weight)
        let currentHeightDisplay = UnitConversion.parseDecimal(height)
        let currentHeadCircumferenceDisplay = UnitConversion.parseDecimal(headCircumference)
        
        weight = UnitConversion.formatDecimal(currentWeightDisplay ?? 0)
        height = UnitConversion.formatDecimal(currentHeightDisplay ?? 0)
        headCircumference = UnitConversion.formatDecimal(currentHeadCircumferenceDisplay ?? 0)
        
        newMetricValue = UnitConversion.formatDecimal(UnitConversion.parseDecimal(newMetricValue) ?? 0)
        
        for (key, value) in customMetrics {
            customMetrics[key] = UnitConversion.formatDecimal(UnitConversion.parseDecimal(value) ?? 0)
        }
    }

    private func saveRecord() {
        formatAllInputs()
        
        guard let weightDisplay = UnitConversion.parseDecimal(weight),
              let heightDisplay = UnitConversion.parseDecimal(height) else {
            print("❗️ Failed to parse values on save.")
            return
        }
        
        let weightInKg = isImperial ? UnitConversion.lbsToKg(weightDisplay) : weightDisplay
        let heightInCm = isImperial ? UnitConversion.inchesToCm(heightDisplay) : heightDisplay
        
        let headCircumferenceCm = UnitConversion.parseDecimal(headCircumference).map {
            isImperial ? UnitConversion.inchesToCm($0) : $0
        }
        
        let metrics = customMetrics.compactMapValues { UnitConversion.parseDecimal($0) }

        record.date = date
        record.weight = weightInKg
        record.height = heightInCm
        record.headCircumference = headCircumferenceCm
        record.customMetrics = metrics

        if isNew {
            profile.weightHeightHistory.append(record)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("❗️ Failed to save record: \(error.localizedDescription)")
        }
    }
}

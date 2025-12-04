import SwiftUI
import SwiftData
import PhotosUI

private enum Gender: String, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { self.rawValue }
}

// A private struct to hold the data being collected during the wizard flow.
fileprivate struct WizardData {
    var name: String = ""
    var birthday: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var gender: Gender = .male
    var weight: String = ""
    var height: String = ""
    var headCircumference: String = ""
    var goal: Goal? = .generalFitness // Default goal
    var activityLevel: ActivityLevel = .sedentary
    var isPregnant: Bool = false
    var isLactating: Bool = false
    var meals: [Meal] = Meal.defaultMeals()
    var trainings: [Training] = Training.defaultTrainings()
    var selectedVitIDs: Set<Vitamin.ID> = []
    var selectedMinIDs: Set<Mineral.ID> = []
    var selectedDiets: Set<Diet.ID> = []
    var selectedAllergens: Set<Allergen.ID> = []
    var hasSeparateStorage: Bool = false
    var selectedSports: Set<Sport.ID> = []
    var selectedPhoto: PhotosPickerItem? = nil
    var photoData: Data? = nil
}

// Enum to define the steps of the wizard.
fileprivate enum WizardStep: Int, Identifiable {
    case name, photo, birthday, gender, height, weight, headCircumference, goal, activity, meals, trainings, sports, vitamins, minerals, diets, allergens, settings, summary

    var id: Int { self.rawValue }

    var title: String {
        switch self {
        case .name: "What's your name?"
        case .photo: "Add your photo"
        case .birthday: "When is your birthday?"
        case .gender: "What's your biological sex?"
        case .height: "What's your height?"
        case .weight: "What's your weight?"
        case .headCircumference: "Head Circumference?"
        case .goal: "What's your main goal?"
        case .activity: "How active are you?"
        case .meals: "Meal Times"
        case .trainings: "Workout Times"
        case .vitamins: "Priority Vitamins"
        case .minerals: "Priority Minerals"
        case .diets: "Any Special Diets?"
        case .allergens: "Any Allergies?"
        case .settings: "Data Storage"
        case .summary: "Confirm Your Details"
        case .sports: "What's your favorite sport?"
        }
    }
    
    var subtitle: String {
        switch self {
        case .name: "Let's get to know you better"
        case .photo: "Choose a profile picture that represents you"
        case .birthday: "This helps us calculate your nutritional needs."
        case .gender: "This helps tailor recommendations."
        case .height: "We use this for calorie calculations."
        case .weight: "We use this for calorie calculations."
        case .headCircumference: "For tracking growth in infants."
        case .goal: "Select a primary goal to tailor your experience."
        case .activity: "To estimate your daily energy needs."
        case .meals: "Set your daily meal schedule."
        case .trainings: "Set your daily workout schedule."
        case .vitamins: "Select vitamins you want to track."
        case .minerals: "Select minerals you want to track."
        case .diets: "Let us know about your dietary preferences."
        case .allergens: "Select any allergies you have."
        case .settings: "Choose how your data is stored."
        case .summary: "Please review your information."
        case .sports: "Help us personalize your fitness journey"
        }
    }
}

struct ProfileWizardView: View {
    // MARK: - Environment & Dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @ObservedObject private var effectManager = EffectManager.shared
    private let calVM = CalendarViewModel.shared
    let isInit: Bool
    let onDismiss: (Profile?) -> Void

    // MARK: - Data Queries
    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]
    @Query(sort: \Diet.name) private var allDiets: [Diet]

    // MARK: - Wizard State
    @State private var currentStep: WizardStep = .name
    @State private var data = WizardData()
    @State private var draftMeal: Meal?
    @State private var draftTraining: Training?
    @State private var path = NavigationPath()

    // MARK: - UI State
    enum FocusableWizardField: Hashable {
        case name, height, weight, headCircumference
    }
    @FocusState private var focusedField: FocusableWizardField?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    private let genders = ["Male", "Female"]
    
    @State private var generatePlanOnFinish = false
    @State private var newlyCreatedProfile: Profile? = nil
    @State private var showAIGenerationView = false

    // MARK: - Picker State & Helpers
    // Two-wheel pickers (whole + decimal) for height & weight
    // For babies (< 2y), the whole-number ranges are narrowed to age‑specific min/max (see helpers below).
    private var heightWholeRange: [Int] {
        if ageInYears < 2 {
            let r = babyWholeRange(for: .height)
            return Array(r)
        } else {
            return isImperial ? Array(12...98) : Array(30...250)
        }
    }

    private var weightWholeRange: [Int] {
        if ageInYears < 2 {
            let r = babyWholeRange(for: .weight)
            return Array(r)
        } else {
            return isImperial ? Array(5...551) : Array(2...250)
        }
    }

    // MARK: - Head Circumference Picker Helpers
    private var headWholeRange: [Int] {
        if ageInYears < 2 {
            let r = babyWholeRange(for: .head)
            return Array(r)
        } else {
            return isImperial ? Array(8...25) : Array(30...55)
        }
    }

    // Age in months helper
    private var ageInMonths: Int {
        Calendar.current.dateComponents([.month], from: data.birthday, to: Date()).month ?? 0
    }

    // Units conversion (local to avoid coupling)
    private func cmToInches(_ cm: Double) -> Double { cm / 2.54 }
    private func kgToLbs(_ kg: Double) -> Double { kg * 2.2046226218 }

    // Metrics we support for baby ranges
    private enum BabyMetric { case height, weight, head }

    /// Returns an inclusive ClosedRange<Int> for the WHOLE number wheel, using month-specific min/max.
    private func babyWholeRange(for metric: BabyMetric) -> ClosedRange<Int> {
        let months = max(0, min(24, ageInMonths))
        let base = babyBoundsBase(forMonths: months, metric: metric) // (min,max) in cm (height/head) or kg (weight)

        let (minVal, maxVal) = base
        if isImperial {
            switch metric {
            case .height, .head:
                let minIn = cmToInches(minVal)
                let maxIn = cmToInches(maxVal)
                let minWhole = max(0, Int(floor(minIn)))
                let maxWhole = max(minWhole, Int(ceil(maxIn)))
                return minWhole...maxWhole
            case .weight:
                let minLb = kgToLbs(minVal)
                let maxLb = kgToLbs(maxVal)
                let minWhole = max(0, Int(floor(minLb)))
                let maxWhole = max(minWhole, Int(ceil(maxLb)))
                return minWhole...maxWhole
            }
        } else {
            // Metric: use cm for height/head, kg for weight
            let minWhole = max(0, Int(floor(minVal)))
            let maxWhole = max(minWhole, Int(ceil(maxVal)))
            return minWhole...maxWhole
        }
    }

    /// Core bounds table (cm for height/head, kg for weight). Interpolates linearly between known month anchors.
    /// If you have a `BabyData` table already, replace the `fallbackAnchors` with your lookup and keep the signature.
    private func babyBoundsBase(forMonths months: Int, metric: BabyMetric) -> (min: Double, max: Double) {
        // Fallback WHO-like anchors for 0, 1, 3, 6, 9, 12, 18, 24 months.
        // Values are intentionally conservative and should be replaced with your BabyData if available.
        typealias R = (min: Double, max: Double)
        let fallbackAnchors: [Int: R]
        switch metric {
        case .height:
            // centimeters
            fallbackAnchors = [
                0:  (45, 55),
                1:  (49, 58),
                3:  (54, 64),
                6:  (60, 72),
                9:  (65, 76),
                12: (70, 82),
                18: (77, 89),
                24: (80, 95),
            ]
        case .weight:
            // kilograms
            fallbackAnchors = [
                0:  (2.5, 4.5),
                1:  (3.0, 5.5),
                3:  (4.5, 7.5),
                6:  (6.0, 9.5),
                9:  (7.0, 11.0),
                12: (8.0, 12.5),
                18: (9.0, 14.0),
                24: (10.0, 16.0),
            ]
        case .head:
            // centimeters (occipitofrontal circumference)
            fallbackAnchors = [
                0:  (32, 37),
                1:  (34, 39),
                3:  (38, 43),
                6:  (41, 46),
                9:  (43, 47),
                12: (44, 48),
                18: (46, 50),
                24: (47, 51),
            ]
        }

        if let exact = fallbackAnchors[months] { return exact }

        // Find surrounding anchors for linear interpolation
        let sortedKeys = fallbackAnchors.keys.sorted()
        let lowerKey = sortedKeys.last(where: { $0 <= months }) ?? 0
        let upperKey = sortedKeys.first(where: { $0 >= months }) ?? 24
        guard lowerKey != upperKey, let low = fallbackAnchors[lowerKey], let up = fallbackAnchors[upperKey] else {
            return fallbackAnchors[lowerKey] ?? fallbackAnchors[24]! // safe fallback
        }

        // Linear interpolation
        let t = Double(months - lowerKey) / Double(upperKey - lowerKey)
        let minV = low.min + (up.min - low.min) * t
        let maxV = low.max + (up.max - low.max) * t
        return (minV, maxV)
    }

    private func currentHeadParts() -> (whole: Int, dec: Int) {
        let raw = UnitConversion.parseDecimal(data.headCircumference) ?? (isImperial ? 16.0 : 40.0)
        let whole = Int(raw.rounded(.down))
        let scale: Double = isImperial ? 100.0 : 10.0
        let maxDec: Int = isImperial ? 99 : 9
        let dec = Int(max(0, min(maxDec, Int((raw * scale).truncatingRemainder(dividingBy: scale)))))
        return (whole, dec)
    }

    private func composeHeadString(whole: Int, dec: Int) -> String {
        let w = max(headWholeRange.first ?? whole, min(whole, headWholeRange.last ?? whole))
        if isImperial {
            let d = max(0, min(99, dec))
            return "\(w)\(decimalSeparator)\(String(format: "%02d", d))"
        } else {
            let d = max(0, min(9, dec))
            return "\(w)\(decimalSeparator)\(d)"
        }
    }

    private var headWholeBinding: Binding<Int> {
        Binding<Int>(
            get: { currentHeadParts().whole },
            set: { newWhole in
                let parts = currentHeadParts()
                data.headCircumference = composeHeadString(whole: newWhole, dec: parts.dec)
            }
        )
    }

    private var headDecimalBinding: Binding<Int> {
        Binding<Int>(
            get: { currentHeadParts().dec },
            set: { newDec in
                let parts = currentHeadParts()
                data.headCircumference = composeHeadString(whole: parts.whole, dec: newDec)
            }
        )
    }
    private let decimalRange: [Int] = Array(0...9)
    private let decimalRangeInches: [Int] = Array(0...99)
    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private func clamp<T: Comparable>(_ value: T, min minV: T, max maxV: T) -> T { max(minV, min(value, maxV)) }

    // MARK: - Picker <-> String bridges (bind wheels directly to $data.height / $data.weight)
    private func currentHeightParts() -> (whole: Int, dec: Int) {
        let raw = UnitConversion.parseDecimal(data.height) ?? (isImperial ? 66.0 : 170.0)
        let whole = Int(raw.rounded(.down))
        let scale: Double = isImperial ? 100.0 : 10.0
        let maxDec: Int = isImperial ? 99 : 9
        let dec = Int(max(0, min(maxDec, Int((raw * scale).truncatingRemainder(dividingBy: scale)))))
        return (whole, dec)
    }

    private func currentWeightParts() -> (whole: Int, dec: Int) {
        let raw = UnitConversion.parseDecimal(data.weight) ?? (isImperial ? 155.0 : 70.0)
        let whole = Int(raw.rounded(.down))
        let dec = Int(max(0, min(9, Int((raw * 10).truncatingRemainder(dividingBy: 10)))))
        return (whole, dec)
    }

    private func composeHeightString(whole: Int, dec: Int) -> String {
        let w = max(heightWholeRange.first ?? whole, min(whole, heightWholeRange.last ?? whole))
        if isImperial {
            let d = max(0, min(99, dec))
            return "\(w)\(decimalSeparator)\(String(format: "%02d", d))"
        } else {
            let d = max(0, min(9, dec))
            return "\(w)\(decimalSeparator)\(d)"
        }
    }

    private func composeWeightString(whole: Int, dec: Int) -> String {
        let w = max(weightWholeRange.first ?? whole, min(whole, weightWholeRange.last ?? whole))
        let d = max(0, min(9, dec))
        return "\(w)\(decimalSeparator)\(d)"
    }

    private var heightWholeBinding: Binding<Int> {
        Binding<Int>(
            get: { currentHeightParts().whole },
            set: { newWhole in
                let parts = currentHeightParts()
                data.height = composeHeightString(whole: newWhole, dec: parts.dec)
            }
        )
    }

    private var heightDecimalBinding: Binding<Int> {
        Binding<Int>(
            get: { currentHeightParts().dec },
            set: { newDec in
                let parts = currentHeightParts()
                data.height = composeHeightString(whole: parts.whole, dec: newDec)
            }
        )
    }

    private var weightWholeBinding: Binding<Int> {
        Binding<Int>(
            get: { currentWeightParts().whole },
            set: { newWhole in
                let parts = currentWeightParts()
                data.weight = composeWeightString(whole: newWhole, dec: parts.dec)
            }
        )
    }

    private var weightDecimalBinding: Binding<Int> {
        Binding<Int>(
            get: { currentWeightParts().dec },
            set: { newDec in
                let parts = currentWeightParts()
                data.weight = composeWeightString(whole: parts.whole, dec: newDec)
            }
        )
    }

    private var bottomPadding: CGFloat {
        isInit ? 20 : 100
    }

    // MARK: - Computed Properties
    private var ageInYears: Int {
        Calendar.current.dateComponents([.year], from: data.birthday, to: Date()).year ?? 0
    }
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    
    private var stepsSequence: [WizardStep] {
        var steps: [WizardStep] = [.name, .photo, .birthday, .gender]
        
        if ageInYears < 2 {
            steps.append(contentsOf: [.height, .weight, .headCircumference])
        } else {
            steps.append(contentsOf: [.height, .weight, .goal, .activity, .sports])
        }
        
        steps.append(contentsOf: [.meals, .trainings, .vitamins, .minerals, .diets, .allergens, .settings, .summary])
        return steps
    }
    
    private var currentStepIndex: Int {
        stepsSequence.firstIndex(of: currentStep) ?? 0
    }
    
    private var totalSteps: Int {
        stepsSequence.count
    }

    private var progressPercentage: Double {
        Double(currentStepIndex + 1) / Double(totalSteps)
    }

    private var isNextDisabled: Bool {
        switch currentStep {
        case .name:
            return data.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .height:
            let heightVal = UnitConversion.parseDecimal(data.height)
            return heightVal == nil || heightVal! <= 0
        case .weight:
            let weightVal = UnitConversion.parseDecimal(data.weight)
            return weightVal == nil || weightVal! <= 0
        case .headCircumference:
            let hcVal = UnitConversion.parseDecimal(data.headCircumference)
            return hcVal == nil || hcVal! <= 0
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                    
                    VStack(spacing: 4) {
                        HStack {
                            Text("Step \(currentStepIndex + 1) of \(totalSteps)")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(progressPercentage * 100))%")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        
                        ProgressView(value: progressPercentage)
                            .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                            .frame(height: 4)
                            .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            .clipShape(Capsule())
                    }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding(.bottom, 20)
                    .padding(.horizontal)

                    VStack(spacing: 20) {
                        VStack(spacing: 16) {
                            Text(currentStep.title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .multilineTextAlignment(.center)
                            
                            Text(currentStep.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Group {
                                switch currentStep {
                                case .name: nameStep
                                case .photo: photoStep
                                case .birthday: birthdayStep
                                case .gender: genderStep
                                case .height: heightStep
                                case .weight: weightStep
                                case .headCircumference: headCircumferenceStep
                                case .goal: goalStep
                                case .activity: activityStep
                                case .meals: mealsStep
                                case .trainings: trainingsStep
                                case .vitamins: vitaminsStep
                                case .minerals: mineralsStep
                                case .diets: dietsStep
                                case .allergens: allergensStep
                                case .settings: settingsStep
                                case .summary: summaryStep
                                case .sports: sportsStep
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity))
                            )
                        }
                        .padding(24)
                        .glassCardStyle(cornerRadius: 30)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.bottom, bottomPadding)
                .disabled(isSaving)
                .blur(radius: isSaving ? 2 : 0)
                
                if isSaving {
                    ProgressView("Saving Profile...")
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .padding(25)
                        .glassCardStyle(cornerRadius: 20)
                        .transition(.opacity.animation(.easeInOut))
                }
            }
            .if(currentStep == .sports ||
                currentStep == .vitamins ||
                currentStep == .minerals ||
                currentStep == .diets ||
                currentStep == .allergens
            ) { $0.ignoresSafeArea(.keyboard, edges: .bottom)}

            .ignoresSafeArea(.container, edges: .bottom)
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage) }
            .onAppear {
                if currentStep == .name {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        focusedField = .name
                    }
                }
            }
            .navigationDestination(item: $draftMeal) { meal in
                MealEditorView(
                    meal: meal,
                    isNew: !data.meals.contains(where: { $0.id == meal.id }),
                    onSave: saveMealFromEditor
                )
            }
            .navigationDestination(item: $draftTraining) { training in
                TrainingEditorView(
                    training: training,
                    isNew: !data.trainings.contains(where: { $0.id == training.id }),
                    onSave: saveTrainingFromEditor
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showAIGenerationView, onDismiss: { onDismiss(newlyCreatedProfile) }) {
                if let profile = newlyCreatedProfile {
                    AIPlanGenerationView(profile: profile) {
                        showAIGenerationView = false
                    }
                }
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            if !isInit {
                Button("Close", action: { onDismiss(nil) })
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
            } else {
                Button("Close", action: { onDismiss(nil) }).hidden()
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
          
            Spacer()
            Text("New Profile")
                .font(.headline)
            Spacer()
            
            Button("Close", action: { onDismiss(nil) }).hidden()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.bottom)
        .padding(.horizontal)
    }

    // MARK: - Step Views
    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != stepsSequence.first {
                Button(action: backStep) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .contentShape(Rectangle())
                }
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .contentShape(Rectangle())
            }

            Button(action: {
                if currentStep == .summary {
                    saveProfile()
                } else {
                    nextStep()
                }
            }) {
                Text(currentStep == .summary ? "Save Profile" : "Continue")
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(isNextDisabled ? effectManager.currentGlobalAccentColor.opacity(0.6) : effectManager.currentGlobalAccentColor)
            .disabled(isNextDisabled)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder private var nameStep: some View {
        VStack(spacing: 20) {
            Spacer()
            StyledLabeledPicker(label: "Name", isRequired: true) {
                ConfigurableTextField(
                    title: "",
                    value: $data.name,
                    type: .standard,
                    placeholderColor: effectManager.currentGlobalAccentColor,
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .name
                )
                .font(.title3)
            }
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var photoStep: some View {
        VStack(spacing: 20) {
            Spacer()
            let imageData = data.photoData
            let color = effectManager.currentGlobalAccentColor.opacity(0.6)
            ZStack {
                VStack{}
                    .frame(width: 252, height: 252)
                    .glassCardStyle(cornerRadius: 126)
                PhotosPicker(selection: $data.selectedPhoto, matching: .images) {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 250, height: 250)
                            .clipShape(Circle())
                        
                    } else {
                        ZStack {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(color)
                                .frame(width: 250, height: 250)
                            Image(systemName: "camera.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(color)
                                .frame(width: 50, height: 50)
                                .padding(.top, 105)
                                .padding(.leading, 155)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: data.selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                self.data.photoData = data
                            }
                        }
                    }
                }
            }
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var birthdayStep: some View {
        VStack {
            Spacer()
            DatePicker("", selection: $data.birthday, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder
    private var genderStep: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                HStack(spacing: 30) {
                    // Изчисляване на диаметъра на бутона на базата на ширината на екрана
                    let buttonDiameter = geometry.size.width / 2 - 45 // 2 е броят на бутоните, 45 е за spacing и padding

                    // Бутон за мъжки пол
                    Button(action: {
                        withAnimation {
                            data.gender = .male
                            data.isPregnant = false
                            data.isLactating = false
                        }
                    }) {
                        Image("m")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .scaledToFit()
                            .frame(width: buttonDiameter, height: buttonDiameter)
                            .padding()
                            .glassCardStyle(cornerRadius: buttonDiameter) // Закръгляне, за да остане кръг
                            .overlay(
                                Circle()
                                    .stroke(data.gender == .male ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    // Бутон за женски пол
                    Button(action: {
                        withAnimation {
                            data.gender = .female
                        }
                    }) {
                        Image("f")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .scaledToFit()
                            .frame(width: buttonDiameter, height: buttonDiameter)
                            .padding()
                            .glassCardStyle(cornerRadius: buttonDiameter) // Закръгляне, за да остане кръг
                            .overlay(
                                Circle()
                                    .stroke(data.gender == .female ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if data.gender == .female && ageInYears >= 14 {
                    VStack(spacing: 16) {
                        Toggle("Pregnant", isOn: $data.isPregnant)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Toggle("Lactating", isOn: $data.isLactating)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .padding(.top, 30)
                    .transition(.opacity.animation(.easeInOut))
                }
                
                Spacer()
                navigationButtons
                    .padding(.top, 10)
            }
            .frame(width: geometry.size.width) // Гарантира, че VStack заема цялата ширина
        }
    }

    
    @ViewBuilder private var heightStep: some View {
        VStack(spacing: 20) {
            Spacer()
            StyledLabeledPicker(label: "Height (\(isImperial ? "in" : "cm"))", isFixedHeight: false, isRequired: true) {
                HStack(spacing: 8) {
                    // Whole number wheel – заменяме стандартния Picker:
                    InfiniteWheelPicker(values: heightWholeRange, selection: heightWholeBinding)

                    Text(decimalSeparator)
                        .font(.title2.weight(.bold))

                    // Decimal wheel – ако искаш и той да е “безкраен”, можеш да ползваш същия компонент
                    if isImperial {
                        InfiniteWheelPicker(values: decimalRangeInches, selection: heightDecimalBinding)
                    } else {
                        InfiniteWheelPicker(values: decimalRange, selection: heightDecimalBinding)
                    }

                    Text(isImperial ? "in" : "cm")
                        .font(.headline)
                        .padding(.leading, 4)
                }
                .frame(height: 180)
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            }
            .onAppear {
                if data.height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let defaultHeight = ageInYears < 2 ? (isImperial ? 25 : 60) : (isImperial ? 66 : 170)
                    data.height = composeHeightString(whole: defaultHeight, dec: 0)
                }
            }
            Spacer()
            navigationButtons
        }
    }

    @ViewBuilder private var weightStep: some View {
        VStack(spacing: 20) {
            Spacer()
            StyledLabeledPicker(label: "Weight (\(isImperial ? "lbs" : "kg"))", isFixedHeight: false, isRequired: true) {
                HStack(spacing: 8) {
                    
                    Picker("Whole", selection: weightWholeBinding) {
                        ForEach(weightWholeRange, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Text(decimalSeparator)
                        .font(.title2.weight(.bold))

                    // Decimal wheel – безкраен (0–9)
                    InfiniteWheelPicker(
                        values: decimalRange,
                        selection: weightDecimalBinding
                    )

                    Text(isImperial ? "lbs" : "kg")
                        .font(.headline)
                        .padding(.leading, 4)
                }
                .frame(height: 180)
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            }
            .onAppear {
                if data.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let defaultWeight = ageInYears < 2 ? (isImperial ? 15 : 7) : (isImperial ? 155 : 70)
                    data.weight = composeWeightString(whole: defaultWeight, dec: 0)
                }
            }
            Spacer()
            navigationButtons
        }
    }

    
    @ViewBuilder private var headCircumferenceStep: some View {
        VStack(spacing: 20) {
            Spacer()
            StyledLabeledPicker(label: "Head Circumference (\(isImperial ? "in" : "cm"))", isFixedHeight: false, isRequired: true) {
                HStack(spacing: 8) {
                    // Whole number wheel – безкраен
                    Picker("Whole", selection: heightWholeBinding) {
                        ForEach(heightWholeRange, id: \.self) { v in
                            Text("\(v)")
                                .tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Text(decimalSeparator)
                        .font(.title2.weight(.bold))

                    // Decimal wheel – безкраен
                    if isImperial {
                        // 00–99 с водеща нула
                        InfiniteWheelPicker(
                            values: decimalRangeInches,
                            selection: headDecimalBinding,
                            labelForValue: { value in
                                String(format: "%02d", value)
                            }
                        )
                    } else {
                        // 0–9 нормално
                        InfiniteWheelPicker(
                            values: decimalRange,
                            selection: headDecimalBinding
                        )
                    }

                    Text(isImperial ? "in" : "cm")
                        .font(.headline)
                        .padding(.leading, 4)
                }
                .frame(height: 180)
                .tint(effectManager.currentGlobalAccentColor)
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            }
            .onAppear {
                if data.headCircumference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    data.headCircumference = composeHeadString(whole: isImperial ? 16 : 40, dec: 0)
                }
            }
            Spacer()
            navigationButtons
        }
    }

    
    @ViewBuilder private var goalStep: some View {
        VStack {
            GoalSelectionView(selectedGoal: $data.goal)
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var activityStep: some View {
        VStack {
            Spacer()
            Picker("Activity Level", selection: $data.activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.description).tag(level)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .tint(effectManager.currentGlobalAccentColor)
            .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            
            Spacer()
            navigationButtons
        }
    }

    @ViewBuilder
    private var mealsStep: some View {
        VStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(data.meals) { meal in
                        mealRow(for: meal)
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Button(action: addMeal) {
                Label("Add Meal", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 12)
            .glassCardStyle(cornerRadius: 20)
            .padding(.top, 12)
            .padding(.bottom)
            .foregroundStyle(effectManager.currentGlobalAccentColor)

            navigationButtons
        }
    }

    @ViewBuilder
    private var trainingsStep: some View {
        VStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(data.trainings) { training in
                        trainingRow(for: training)
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Button(action: addTraining) {
                Label("Add Workout", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .contentShape(Rectangle())
            }
            
            .padding(.vertical, 12)
            .glassCardStyle(cornerRadius: 20)
            .padding(.top, 12)
            .padding(.bottom)
            .foregroundStyle(effectManager.currentGlobalAccentColor)

            navigationButtons
        }
    }

    @ViewBuilder private var vitaminsStep: some View {
           VStack {
               // Заменете IconMultiSelectGridView с ColorTextMultiSelectGridView
               ColorTextMultiSelectGridView(
                   items: allVitamins,
                   selection: $data.selectedVitIDs,
                   searchPrompt: "Search vitamins...",
                   itemContentSize: CGSize(width: 48, height: 48) // Задаваме размер за съдържанието
               )

               Spacer()
               navigationButtons
           }
       }
       
       @ViewBuilder private var mineralsStep: some View {
           VStack {
               // Заменете IconMultiSelectGridView с ColorTextMultiSelectGridView
               ColorTextMultiSelectGridView(
                   items: allMinerals,
                   selection: $data.selectedMinIDs,
                   searchPrompt: "Search minerals...",
                   itemContentSize: CGSize(width: 48, height: 48) // Задаваме размер за съдържанието
               )
               Spacer()
               navigationButtons
           }
       }
    
    private var dietsStep: some View {
        VStack {
            ColorTextMultiSelectGridView(
                items: allDiets,                             // [Diet]
                selection: $data.selectedDiets,             // Set<Diet.ID> (String)
                searchPrompt: "Search diets...",
                itemContentSize: CGSize(width: 0, height: 56) // височина на реда
            )

            Spacer()
            navigationButtons
        }
    }

    @ViewBuilder private var allergensStep: some View {
        VStack {
            IconMultiSelectGridView(items: Allergen.allCases.sorted { $0.rawValue < $1.rawValue }, selection: $data.selectedAllergens, searchPrompt:  "Search allergens...", iconSize: CGSize(width: 120, height: 120), useIconColor: true, dissableText: true)

            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var sportsStep: some View {
        VStack {
            IconMultiSelectGridView(items: Sport.allCases.sorted { $0.rawValue < $1.rawValue }, selection: $data.selectedSports, searchPrompt:  "Search sports...", iconSize: CGSize(width: 48, height: 48), useIconColor: false)
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var settingsStep: some View {
        VStack {
            Toggle(isOn: $data.hasSeparateStorage) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate Storage & Lists")
                    Text("This profile will have its own private storage and shopping lists.")
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding(.vertical)
            
            Spacer()
            navigationButtons
        }
    }
    
    @ViewBuilder private var summaryStep: some View {
        VStack {
            List {
                Group {
                    SummaryRow(label: "Name", value: data.name)
                    SummaryRow(label: "Birthday", value: data.birthday.formatted(date: .long, time: .omitted))
                    SummaryRow(label: "Gender", value: data.gender.rawValue)
                    SummaryRow(label: "Height", value: "\(data.height) \(isImperial ? "in" : "cm")")
                    SummaryRow(label: "Weight", value: "\(data.weight) \(isImperial ? "lbs" : "kg")")
                    if ageInYears < 2 { SummaryRow(label: "Head Circ.", value: "\(data.headCircumference) \(isImperial ? "in" : "cm")") }
                    if let goal = data.goal { SummaryRow(label: "Goal", value: goal.title) }
                    if ageInYears >= 2 { SummaryRow(label: "Activity", value: data.activityLevel.description) }
                    if ageInYears >= 14 {
                        if data.isPregnant { SummaryRow(label: "Condition", value: "Pregnant") }
                        if data.isLactating { SummaryRow(label: "Condition", value: "Lactating") }
                    }
                    if !data.selectedVitIDs.isEmpty { SummaryRow(label: "Vitamins", value: "\(data.selectedVitIDs.count) selected") }
                    if !data.selectedMinIDs.isEmpty { SummaryRow(label: "Minerals", value: "\(data.selectedMinIDs.count) selected") }
                    if !data.selectedDiets.isEmpty { SummaryRow(label: "Diets", value: "\(data.selectedDiets.count) selected") }
                    if !data.selectedAllergens.isEmpty { SummaryRow(label: "Allergens", value: "\(data.selectedAllergens.count) selected") }
                    if !data.selectedSports.isEmpty { SummaryRow(label: "Sports", value: "\(data.selectedSports.count) selected") }
                    SummaryRow(label: "Data Storage", value: data.hasSeparateStorage ? "Separate" : "Shared")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Toggle(isOn: $generatePlanOnFinish) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate First Weekly Meal Plan")
                    Text("Uses USDA foods, respecting your diet, allergens, and nutrient priorities.")
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding(.vertical)

            Spacer()
            
            navigationButtons
        }
    }
    
    // MARK: - Helper Views & Functions
    private func mealRow(for meal: Meal) -> some View {
        HStack(alignment: .center) {
            Text(meal.name)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            Spacer()
            Text("\(meal.startTime.formatted(date: .omitted, time: .shortened)) – \(meal.endTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            Button { deleteMeal(meal) } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor, effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2))
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .contentShape(Rectangle())
        .onTapGesture { editMeal(meal) }
    }

    private func trainingRow(for training: Training) -> some View {
        HStack(alignment: .center) {
            Text(training.name)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            Spacer()
            Text("\(training.startTime.formatted(date: .omitted, time: .shortened)) – \(training.endTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            Button { deleteTraining(training) } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor, effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2))
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .contentShape(Rectangle())
        .onTapGesture { editTraining(training) }
    }
    
    private func SummaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(effectManager.currentGlobalAccentColor)
        }
    }

    // MARK: - Navigation & Logic
    private func nextStep() {
        focusedField = nil
        withAnimation(.easeInOut) {
            guard let currentIndex = stepsSequence.firstIndex(of: currentStep) else { return }
            if currentIndex < stepsSequence.count - 1 {
                currentStep = stepsSequence[currentIndex + 1]
            }
        }
        let simpleSteps: [WizardStep] = [.name, .height, .weight, .headCircumference]
        if simpleSteps.contains(currentStep) {
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = simpleSteps.first(where: { $0 == currentStep }).map { step -> FocusableWizardField in
                    switch step {
                    case .name: return .name
                    case .height: return .height
                    case .weight: return .weight
                    case .headCircumference: return .headCircumference
                    default: fatalError("Unreachable case in wizard focus")
                    }
                }
            }
        }
    }

    private func backStep() {
        focusedField = nil
        withAnimation(.easeInOut) {
            guard let currentIndex = stepsSequence.firstIndex(of: currentStep) else { return }
            if currentIndex > 0 {
                currentStep = stepsSequence[currentIndex - 1]
            }
        }
    }
    
    // MARK: - Logic & Meal/Training Management
    private func addMeal() {
        draftMeal = Meal(name: "", startTime: Date(), endTime: Date().addingTimeInterval(3600))
        if let draftMeal { path.append(draftMeal) }
    }

    private func editMeal(_ meal: Meal) {
        draftMeal = meal
        path.append(meal)
    }

    private func deleteMeal(_ meal: Meal) {
        withAnimation {
            data.meals.removeAll { $0.id == meal.id }
        }
    }

    private func saveMealFromEditor(_ updatedMeal: Meal) {
        if let index = data.meals.firstIndex(where: { $0.id == updatedMeal.id }) {
            data.meals[index].name = updatedMeal.name
            data.meals[index].startTime = updatedMeal.startTime
            data.meals[index].endTime = updatedMeal.endTime
            data.meals[index].reminderMinutes = updatedMeal.reminderMinutes
        } else {
            data.meals.append(updatedMeal)
        }
        data.meals.sort { $0.startTime < $1.startTime }
    }
    
    private func addTraining() {
        draftTraining = Training(name: "", startTime: Date(), endTime: Date().addingTimeInterval(3600))
        if let draft = draftTraining { path.append(draft) }
    }

    private func editTraining(_ training: Training) {
        draftTraining = training
        path.append(training)
    }

    private func deleteTraining(_ training: Training) {
        withAnimation {
            data.trainings.removeAll { $0.id == training.id }
        }
    }

    private func saveTrainingFromEditor(_ updatedTraining: Training) {
        if let index = data.trainings.firstIndex(where: { $0.id == updatedTraining.id }) {
            data.trainings[index].name = updatedTraining.name
            data.trainings[index].startTime = updatedTraining.startTime
            data.trainings[index].endTime = updatedTraining.endTime
            data.trainings[index].reminderMinutes = updatedTraining.reminderMinutes
        } else {
            data.trainings.append(updatedTraining)
        }
        data.trainings.sort { $0.startTime < $1.startTime }
    }
    
    private func saveProfile() {
        Task { @MainActor in
            isSaving = true
            
            guard let weightDisplay = UnitConversion.parseDecimal(data.weight),
                  let heightDisplay = UnitConversion.parseDecimal(data.height) else {
                alertMessage = "Please enter valid numbers for weight and height."; showAlert = true; isSaving = false; return
            }

            let weightInKg = isImperial ? UnitConversion.lbsToKg(weightDisplay) : weightDisplay
            let heightInCm = isImperial ? UnitConversion.inchesToCm(heightDisplay) : heightDisplay
            
            let headCircumferenceCm = UnitConversion.parseDecimal(data.headCircumference).map {
                isImperial ? UnitConversion.inchesToCm($0) : $0
            }

            let chosenVitamins = allVitamins.filter { data.selectedVitIDs.contains($0.id) }
            let chosenMinerals = allMinerals.filter { data.selectedMinIDs.contains($0.id) }
            let chosenDiets = allDiets.filter { data.selectedDiets.contains($0.id) }
            let chosenAllergens = data.selectedAllergens.compactMap { Allergen(rawValue: $0) }
            let chosenSports = Sport.allCases.filter { data.selectedSports.contains($0.id) }

            let newProfile = Profile(
                name: data.name, birthday: data.birthday, gender: data.gender.rawValue,
                weight: weightInKg, height: heightInCm, goal: data.goal, meals: data.meals,
                trainings: data.trainings, sports: chosenSports,
                activityLevel: data.activityLevel, isPregnant: data.isPregnant,
                isLactating: data.isLactating,
                priorityVitamins: chosenVitamins, priorityMinerals: chosenMinerals,
                diets: chosenDiets, allergens: chosenAllergens,
                photoData: data.photoData,
                hasSeparateStorage: data.hasSeparateStorage
            )
            
            let initialRecord = WeightHeightRecord(
                date: .now,
                weight: weightInKg,
                height: heightInCm,
                headCircumference: headCircumferenceCm
            )
            newProfile.weightHeightHistory.append(initialRecord)
            
            modelContext.insert(newProfile)

            do {
                try modelContext.save()
                print("[WizardSave] SwiftData saved profile successfully.")

                guard await calVM.requestCalendarAccessIfNeeded() else {
                    alertMessage = "Calendar access is required. Please grant permission in Settings."; showAlert = true; isSaving = false; return
                }
                
                calVM.createOrUpdateCalendar(for: newProfile)
                await calVM.createOrUpdateShoppingListCalendar(for: newProfile, context: modelContext)

                isSaving = false
                
                if generatePlanOnFinish {
                    self.newlyCreatedProfile = newProfile
                    self.showAIGenerationView = true
                } else {
                    onDismiss(newProfile)
                }

            } catch {
                alertMessage = "Failed to save profile: \(error.localizedDescription)"
                showAlert = true
                isSaving = false
            }
        }
    }
}

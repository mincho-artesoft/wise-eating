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
    var meals: [Meal] = Meal.defaultMeals()
    var trainings: [Training] = Training.defaultTrainings()
    var selectedVitIDs: Set<Vitamin.ID> = []
    var selectedMinIDs: Set<Mineral.ID> = []
    var selectedAllergens: Set<Allergen.ID> = []
    var hasSeparateStorage: Bool = false
    var selectedPhoto: PhotosPickerItem? = nil
    var photoData: Data? = nil
    var ayurvedaConstitution: AyurvedaConstitutionDraft? = nil
}

// Enum to define the steps of the wizard.
fileprivate enum WizardStep: Int, Identifiable {
    case name, photo, birthday, gender, height, weight, meals, trainings, vitamins, minerals, allergens, constitution, summary

    var id: UUID { Self.stableIDs[rawValue] }

    private static let stableIDs: [UUID] = [
        UUID(uuidString: "E16BE25C-9D63-5DFB-93DF-ABF0C695D36C")!,
        UUID(uuidString: "3B78288C-14E6-5F68-9260-C3F2BF284A5D")!,
        UUID(uuidString: "4551C432-B3D8-53E6-8BE5-9E326D4095FE")!,
        UUID(uuidString: "DFDBCA54-9BEF-52AF-ACF9-37CA60990ABC")!,
        UUID(uuidString: "81DE1EB9-6B72-5CC0-8E5C-AFAB0F2FDC20")!,
        UUID(uuidString: "BDE9A40C-A4DC-5AA1-AB1C-CD6715F8667D")!,
        UUID(uuidString: "7E7C42DF-396D-54A2-B39A-7AF27432AABC")!,
        UUID(uuidString: "C7A21808-AC78-50AB-87E8-095680592A2C")!,
        UUID(uuidString: "76FF218C-EC3D-5982-8D45-D13723A8355F")!,
        UUID(uuidString: "AFA75CF7-B523-5DCA-B26C-D2BEBED23C61")!,
        UUID(uuidString: "8FB0B362-856D-5722-8D47-F7991A8EF75E")!,
        UUID(uuidString: "284D50DA-2DE5-5107-A7C2-9728118077DE")!,
        UUID(uuidString: "0C4A33AA-0509-54AE-9AE3-0E79168C3A49")!,
    ]

    var title: String {
        switch self {
        case .name: "What's your name?"
        case .photo: "Add your photo"
        case .birthday: "When is your birthday?"
        case .gender: "What's your biological sex?"
        case .height: "What's your height?"
        case .weight: "What's your weight?"
        case .meals: "Meal Times"
        case .trainings: "Workout Times"
        case .vitamins: "Priority Vitamins"
        case .minerals: "Priority Minerals"
        case .allergens: "Any Allergies?"
        case .constitution: "Your traditional constitution"
        case .summary: "Confirm Your Details"
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
        case .meals: "Set your daily meal schedule."
        case .trainings: "Set your daily workout schedule."
        case .vitamins: "Select vitamins you want to track."
        case .minerals: "Select minerals you want to track."
        case .allergens: "Select any allergies you have."
        case .constitution: "Choose your constitution or answer 12 questions."
        case .summary: "Please review your information."
        }
    }
}

struct ProfileWizardView: View {
    // MARK: - Environment & Dependencies
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    private let calVM = CalendarViewModel.shared
    let isInit: Bool
    let onDismiss: (Profile?) -> Void
    @State private var showPhotoSourceDialog = false
    @State private var isShowingCameraPicker = false
    @State private var isShowingPhotoLibraryPicker = false
    // MARK: - Data Queries
    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]

    // MARK: - Wizard State
    @State private var currentStep: WizardStep = .name
    @State private var data = WizardData()
    @State private var draftMeal: Meal?
    @State private var draftTraining: Training?
    @State private var path = NavigationPath()
    @State private var scheduledConstitution: AyurvedaDoshaDistribution?

    // MARK: - UI State
    enum FocusableWizardField: Hashable {
        case name, height, weight
    }
    @FocusState private var focusedField: FocusableWizardField?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    @State private var constitutionStepTitle = "Your traditional constitution"
    @State private var constitutionStepSubtitle = "Choose your constitution or answer 12 questions."
    private let genders = ["Male", "Female"]
    
    @State private var generatePlanOnFinish = false
    @State private var newlyCreatedProfile: Profile? = nil
    @State private var showAIGenerationView = false

    @State private var isShowingFullScreenPhoto = false
    @State private var fullScreenUIImage: UIImage? = nil
    // MARK: - Picker State & Helpers
    // Two-wheel pickers (whole + decimal) for height & weight
    // MARK: - Picker State & Helpers

    // Универсален обхват за Ръст (от бебета до високи възрастни)
    private var heightWholeRange: [Int] {
        if isImperial {
            return Array(10...100) // Инчове: ~25см до 254см
        } else {
            return Array(30...250) // Сантиметри
        }
    }

    // Универсален обхват за Тегло
    private var weightWholeRange: [Int] {
        if isImperial {
            return Array(4...660) // Паунди
        } else {
            return Array(2...300) // Килограми
        }
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
        
        steps.append(contentsOf: [.height, .weight, .constitution])
        
        steps.append(contentsOf: [.meals, .trainings, .vitamins, .minerals, .allergens])
        steps.append(.summary)
        return steps
    }
    
    private var currentStepIndex: Int {
        stepsSequence.firstIndex(of: currentStep) ?? 0
    }
    
    private var totalSteps: Int {
        stepsSequence.count
    }

    private var progressPercentage: Double {
        guard totalSteps > 1 else { return 1 }
        return Double(currentStepIndex) / Double(totalSteps - 1)
    }

    private var progressPercentLabel: Int {
        Int((progressPercentage * 100).rounded())
    }

    private var displayedStepTitle: String {
        currentStep == .constitution ? constitutionStepTitle : currentStep.title
    }

    private var displayedStepSubtitle: String {
        currentStep == .constitution ? constitutionStepSubtitle : currentStep.subtitle
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
                            Text("\(progressPercentLabel)%")
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
                            Text(displayedStepTitle)
                                .font(.title.weight(.bold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .multilineTextAlignment(.center)
                            
                            Text(displayedStepSubtitle)
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
                                case .meals: mealsStep
                                case .trainings: trainingsStep
                                case .vitamins: vitaminsStep
                                case .minerals: mineralsStep
                                case .allergens: allergensStep
                                case .constitution: constitutionStep
                                case .summary: summaryStep
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
                // Фон / glass кръг
                VStack { }
                    .frame(width: 252, height: 252)
                    .glassCardStyle(cornerRadius: 126)

                if let imageData,
                   let uiImage = UIImage(data: imageData) {

                    // 👉 Tap на аватара = fullscreen
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 250, height: 250)
                        .clipShape(Circle())
                        .onTapGesture {
                            fullScreenUIImage = uiImage
                            isShowingFullScreenPhoto = true
                        }

                    // 📷 Малък бутон долу-дясно = избор на източник
                    Button {
                        showPhotoSourceDialog = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 90, y: 90)

                } else {
                    // Нямаме снимка – целият кръг отваря диалог за източник
                    Button {
                        showPhotoSourceDialog = true
                    } label: {
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
                    .buttonStyle(.plain)
                }
            }
            // 🔽 ТУК Е ДИАЛОГЪТ – САМО 2 ОПЦИИ + Cancel
            .confirmationDialog("Select photo source", isPresented: $showPhotoSourceDialog) {
                Button("Take Photo") {
                    isShowingCameraPicker = true
                }
                Button("Photo Library") {
                    isShowingPhotoLibraryPicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            // 📷 Камера
            .sheet(isPresented: $isShowingCameraPicker) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        self.data.photoData = data
                    }
                }
                .presentationCornerRadius(20)
            }
            // 🖼 Фото библиотека
            .sheet(isPresented: $isShowingPhotoLibraryPicker) {
                PhotoLibraryPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        self.data.photoData = data
                    }
                }
                .presentationCornerRadius(20)
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
                .environment(\.colorScheme, effectManager.appColorScheme)
            
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
                .environment(\.colorScheme, effectManager.appColorScheme)
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
                .environment(\.colorScheme, effectManager.appColorScheme)
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
            ColorTextMultiSelectGridView(
                items: allVitamins,
                selection: $data.selectedVitIDs,
                searchPrompt: "Search vitamins...",
                itemContentSize: CGSize(width: 48, height: 48),
                itemLabel: { vitamin in
                    vitamin.abbreviation.replacingOccurrences(
                        of: "Vit ",
                        with: "Vitamin "
                    )
                }
            )
            Spacer()
            navigationButtons
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // ✅ ДОБАВЕНО
    }

    @ViewBuilder private var mineralsStep: some View {
        VStack {
            ColorTextMultiSelectGridView(
                items: allMinerals,
                selection: $data.selectedMinIDs,
                searchPrompt: "Search minerals...",
                itemContentSize: CGSize(width: 48, height: 48)
            )
            Spacer()
            navigationButtons
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // ✅ ДОБАВЕНО
    }

    @ViewBuilder private var allergensStep: some View {
        VStack {
            IconMultiSelectGridView(
                items: Allergen.allCases.sorted { $0.rawValue < $1.rawValue },
                selection: $data.selectedAllergens,
                searchPrompt: "Search allergens...",
                iconSize: CGSize(width: 120, height: 120),
                useIconColor: true,
                dissableText: true
            )
            Spacer()
            navigationButtons
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // ✅ ДОБАВЕНО
    }
    
    @ViewBuilder private var constitutionStep: some View {
        AyurvedaConstitutionOnboardingStepView(
            draft: $data.ayurvedaConstitution,
            onBack: backStep,
            onContinue: continueFromConstitution,
            onHeaderChange: { title, subtitle in
                constitutionStepTitle = title
                constitutionStepSubtitle = subtitle
            }
        )
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
                    if !data.selectedVitIDs.isEmpty { SummaryRow(label: "Vitamins", value: "\(data.selectedVitIDs.count) selected") }
                    if !data.selectedMinIDs.isEmpty { SummaryRow(label: "Minerals", value: "\(data.selectedMinIDs.count) selected") }
                    if !data.selectedAllergens.isEmpty { SummaryRow(label: "Allergens", value: "\(data.selectedAllergens.count) selected") }
                    if let constitution = data.ayurvedaConstitution {
                        SummaryRow(label: "Ayurvedic Profile", value: constitution.result.label)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(spacing: 12) {
                Toggle(isOn: $data.hasSeparateStorage) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Separate Storage & Lists")
                        Text("This profile will have its own private storage and shopping lists.")
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }

                Toggle(isOn: $generatePlanOnFinish) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate First Weekly Meal Plan")
                        Text("Uses USDA foods, respecting your allergens and nutrient priorities.")
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
            }
            .environment(\.colorScheme, effectManager.appColorScheme)
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
        let simpleSteps: [WizardStep] = [.name, .height, .weight]
        if simpleSteps.contains(currentStep) {
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = simpleSteps.first(where: { $0 == currentStep }).map { step -> FocusableWizardField in
                    switch step {
                    case .name: return .name
                    case .height: return .height
                    case .weight: return .weight
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

    private struct DoshaTimeAnchors {
        let vata: Int
        let pitta: Int
        let kapha: Int

        func blendedMinutes(
            for distribution: AyurvedaDoshaDistribution,
            roundedTo interval: Int = 5
        ) -> Int {
            let minutes = Int((
                distribution.vata * Double(vata) +
                distribution.pitta * Double(pitta) +
                distribution.kapha * Double(kapha)
            ).rounded())
            guard interval > 1 else { return minutes }
            return Int((Double(minutes) / Double(interval)).rounded()) * interval
        }
    }

    private func continueFromConstitution() {
        if let distribution = data.ayurvedaConstitution?.prakriti,
           distribution != scheduledConstitution {
            applyDinacharyaDefaults(for: distribution)
            scheduledConstitution = distribution
        }
        nextStep()
    }

    private func applyDinacharyaDefaults(
        for distribution: AyurvedaDoshaDistribution
    ) {
        // The daily dosha clock is shared. These anchors only personalize where
        // inside the researched Dinacharya windows each default should sit.
        let exercise = DoshaTimeAnchors(vata: 420, pitta: 390, kapha: 360)
        let exerciseDuration = DoshaTimeAnchors(vata: 30, pitta: 40, kapha: 50)
        let breakfast = DoshaTimeAnchors(vata: 480, pitta: 480, kapha: 510)
        let lunch = DoshaTimeAnchors(vata: 735, pitta: 720, kapha: 750)
        let dinner = DoshaTimeAnchors(vata: 1_110, pitta: 1_110, kapha: 1_080)

        let exerciseStartMinutes = exercise.blendedMinutes(for: distribution)
        let exerciseDurationMinutes = exerciseDuration.blendedMinutes(
            for: distribution
        )
        let suggestedBreakfastMinutes = breakfast.blendedMinutes(
            for: distribution
        )
        let breakfastStartMinutes = max(
            suggestedBreakfastMinutes,
            exerciseStartMinutes + exerciseDurationMinutes + 30
        )

        let exerciseStart = wizardTime(minutesFromMidnight: exerciseStartMinutes)
        let exerciseEnd = wizardTime(
            minutesFromMidnight: exerciseStartMinutes + exerciseDurationMinutes
        )
        let breakfastStart = wizardTime(minutesFromMidnight: breakfastStartMinutes)
        let lunchStart = wizardTime(
            minutesFromMidnight: lunch.blendedMinutes(for: distribution)
        )
        let dinnerStart = wizardTime(
            minutesFromMidnight: dinner.blendedMinutes(for: distribution)
        )

        let mealDuration: TimeInterval = 2 * 60 * 60
        data.meals = [
            Meal(
                name: "Breakfast",
                startTime: breakfastStart,
                endTime: breakfastStart.addingTimeInterval(mealDuration)
            ),
            Meal(
                name: "Lunch",
                startTime: lunchStart,
                endTime: lunchStart.addingTimeInterval(mealDuration)
            ),
            Meal(
                name: "Dinner",
                startTime: dinnerStart,
                endTime: dinnerStart.addingTimeInterval(mealDuration)
            ),
        ]

        data.trainings = [
            Training(
                name: "Morning Workout",
                startTime: exerciseStart,
                endTime: exerciseEnd
            ),
        ]
    }

    private func wizardTime(minutesFromMidnight: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        return calendar.date(
            byAdding: .minute,
            value: minutesFromMidnight,
            to: startOfDay
        ) ?? startOfDay
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
            
            let chosenVitamins = allVitamins.filter { data.selectedVitIDs.contains($0.id) }
            let chosenMinerals = allMinerals.filter { data.selectedMinIDs.contains($0.id) }
            let chosenAllergens = data.selectedAllergens.compactMap { Allergen(rawValue: $0) }
            let newProfile = Profile(
                name: data.name, birthday: data.birthday, gender: data.gender.rawValue,
                weight: weightInKg, height: heightInCm, meals: data.meals,
                trainings: data.trainings,
                priorityVitamins: chosenVitamins, priorityMinerals: chosenMinerals,
                allergens: chosenAllergens,
                photoData: data.photoData,
                hasSeparateStorage: data.hasSeparateStorage
            )
            
            modelContext.insert(newProfile)

            do {
                try modelContext.save()
                print("[WizardSave] SwiftData saved profile successfully.")

                if let constitution = data.ayurvedaConstitution {
                    AyurvedaConstitutionStore.save(
                        constitution,
                        for: newProfile.id
                    )
                }

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

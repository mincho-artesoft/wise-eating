import SwiftUI
import SwiftData
import PhotosUI

@MainActor
struct FoodItemEditorView: View {
    @State private var showPhotoSourceDialog = false
    @State private var isShowingCameraPicker = false
    @State private var isShowingPhotoLibraryPicker = false

    @ObservedObject private var aiManager = AIManager.shared // Add this
       @State private var hasUserMadeEdits: Bool = true // Add this
       @State private var runningGenerationJobID: UUID? = nil // Add this
       @State private var showAIGenerationToast = false // Add this
       @State private var toastTimer: Timer? = nil // Add this
       @State private var toastProgress: Double = 0.0 // Add this
    
    // --- AI Floating Button: State ---
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingFoodAIButtonPosition"
    @State private var isGeneratingAIData = false

    
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var ctx
    
    private enum FocusableField: Hashable {
        case name, description, prepTime, minAge, servingWeight
        case carbohydrates, protein, fat, fiber, totalSugars, energyKcal
        case vitaminA_RAE, retinol, caroteneAlpha, caroteneBeta, cryptoxanthinBeta, luteinZeaxanthin, lycopene
        case vitaminB1_Thiamin, vitaminB2_Riboflavin, vitaminB3_Niacin, vitaminB5_PantothenicAcid, vitaminB6
        case folateDFE, folateFood, folateTotal, folicAcid, vitaminB12
        case vitaminC, vitaminD, vitaminE, vitaminK, choline
        case calcium, phosphorus, magnesium, potassium, sodium, iron, zinc, copper, manganese, selenium, fluoride
        case totalSaturated, totalMonounsaturated, totalPolyunsaturated, totalTrans, totalTransMonoenoic, totalTransPolyenoic
        case sfa4_0, sfa6_0, sfa8_0, sfa10_0, sfa12_0, sfa13_0, sfa14_0, sfa15_0, sfa16_0, sfa17_0, sfa18_0, sfa20_0, sfa22_0, sfa24_0
        case mufa14_1, mufa15_1, mufa16_1, mufa17_1, mufa18_1, mufa20_1, mufa22_1, mufa24_1
        case tfa16_1_t, tfa18_1_t, tfa22_1_t, tfa18_2_t
        case pufa18_2, pufa18_3, pufa18_4, pufa20_2, pufa20_3, pufa20_4, pufa20_5, pufa21_5, pufa22_4, pufa22_5, pufa22_6, pufa2_4
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        case alcoholEthyl, caffeine, theobromine, cholesterol, water, ash, betaine, alkalinityPH
        // --- КРАЙ НА ПРОМЯНАТА ---
        case alanine, arginine, asparticAcid, cystine, glutamicAcid, glycine, histidine, isoleucine, leucine, lysine, methionine, phenylalanine, proline, threonine, tryptophan, tyrosine, valine, serine, hydroxyproline
        case starch, sucrose, glucose, fructose, lactose, maltose, galactose
        case phytosterols, betaSitosterol, campesterol, stigmasterol
    }
    
    @FocusState private var focusedField: FocusableField?
    
    let onDismiss: (FoodItem?) -> Void

    let food: FoodItem?
    let dubFood: FoodItemCopy?
    var profile: Profile?

    @State private var name: String
    @State private var itemDescription: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedCategories: Set<FoodCategory.ID>
    @State private var selectedDiets: Set<Diet.ID>
    @State private var selectedAllergens: Set<Allergen.ID>
    
    @State private var showMacros = true
    @State private var showLipids = false
    @State private var showOther = false
    @State private var showMoreVitamins  = false
    @State private var showMoreMinerals = false
    @State private var showAminoAcids = false
    @State private var showCarbDetails = false
    @State private var showSterols = false
    
    enum OpenMenu { case none, category, diet, allergen }
    @State private var openMenu: OpenMenu = .none
    
    @State private var macros: MacroForm
    @State private var lipids: LipidForm
    @State private var vitamins: VitaminForm
    @State private var minerals: MineralForm
    @State private var others: OtherForm
    @State private var aminoAcids: AminoAcidsForm
    @State private var carbDetails: CarbDetailsForm
    @State private var sterols: SterolsForm
    
    @State private var showAlert = false
    @State private var alertMsg = ""
    
    @State private var servingWeightString: String
    @State private var minAgeMonthsTxt: String

    @State private var isSaving = false
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var servingUnit: String { isImperial ? "oz" : "g" }
    
    @Query(sort: \Diet.name) private var allDiets: [Diet]

    init(dubFood: FoodItemCopy? = nil, food: FoodItem? = nil, profile: Profile? = nil, onDismiss: @escaping (FoodItem?) -> Void, isAIInit: Bool? = false) {
        self.dubFood = dubFood
        self.food = food
        self.profile = profile
        self.onDismiss = onDismiss

        var initialName = ""
        var initialDescription = ""
        var initialPhotoData: Data? = nil
        var initialMinAgeMonthsTxt = ""
        var initialSelectedCategories = Set<FoodCategory.ID>()
        var initialSelectedDiets = Set<Diet.ID>()
        var initialSelectedAllergens = Set<Allergen.ID>()
        var initialMacros = MacroForm()
        var initialLipids = LipidForm()
        var initialVitamins = VitaminForm()
        var initialMinerals = MineralForm()
        var initialOthers = OtherForm()
        var initialAminoAcids = AminoAcidsForm()
        var initialCarbDetails = CarbDetailsForm()
        var initialSterols = SterolsForm()
        
        if let dub = dubFood {
            
            initialName = isAIInit! ? dub.name : "Copy of \(dub.name)"
            initialPhotoData = dub.photo
            initialDescription = dub.itemDescription ?? ""
            initialSelectedCategories = Set(dub.category?.map(\.id) ?? [])
            initialSelectedDiets = Set(dub.dietIDs ?? [])
            initialSelectedAllergens = Set(dub.allergens?.map(\.id) ?? [])
            initialMacros = MacroForm(from: dub.macronutrients?.toOriginal())
            initialLipids = LipidForm(from: dub.lipids?.toOriginal())
            initialVitamins = VitaminForm(from: dub.vitamins?.toOriginal())
            initialMinerals = MineralForm(from: dub.minerals?.toOriginal())
            initialOthers = OtherForm(from: dub.other?.toOriginal())
            initialAminoAcids = AminoAcidsForm(from: dub.aminoAcids?.toOriginal())
            initialCarbDetails = CarbDetailsForm(from: dub.carbDetails?.toOriginal())
            initialSterols = SterolsForm(from: dub.sterols?.toOriginal())
        } else if let f = food {
            initialName = f.name
            initialPhotoData = f.photo
            initialDescription = f.itemDescription ?? ""
            initialMinAgeMonthsTxt = f.minAgeMonths > 0 ? String(f.minAgeMonths) : ""
            initialSelectedCategories = Set(f.category?.map(\.id) ?? [])
            initialSelectedDiets = Set(f.diets?.map(\.id) ?? [])
            initialSelectedAllergens = Set(f.allergens?.map(\.id) ?? [])
            initialMacros = MacroForm(from: f.macronutrients)
            initialLipids = LipidForm(from: f.lipids)
            initialVitamins = VitaminForm(from: f.vitamins)
            initialMinerals = MineralForm(from: f.minerals)
            initialOthers = OtherForm(from: f.other)
            initialAminoAcids = AminoAcidsForm(from: f.aminoAcids)
            initialCarbDetails = CarbDetailsForm(from: f.carbDetails)
            initialSterols = SterolsForm(from: f.sterols)
        }

        _name = State(initialValue: initialName)
        _itemDescription = State(initialValue: initialDescription)
        _photoData = State(initialValue: initialPhotoData)
        _minAgeMonthsTxt = State(initialValue: initialMinAgeMonthsTxt)
        _selectedCategories = State(initialValue: initialSelectedCategories)
        _selectedDiets = State(initialValue: initialSelectedDiets)
        _selectedAllergens = State(initialValue: initialSelectedAllergens)
        _macros = State(initialValue: initialMacros)
        _lipids = State(initialValue: initialLipids)
        _vitamins = State(initialValue: initialVitamins)
        _minerals = State(initialValue: initialMinerals)
        _others = State(initialValue: initialOthers)
        _aminoAcids = State(initialValue: initialAminoAcids)
        _carbDetails = State(initialValue: initialCarbDetails)
        _sterols = State(initialValue: initialSterols)

        let initialServingWeightG = initialOthers.weightG?.value
        var initialDisplayWeightString = ""
        if let grams = initialServingWeightG {
            let isImperial = GlobalState.measurementSystem == "Imperial"
            if isImperial {
                initialDisplayWeightString = UnitConversion.formatDecimal(UnitConversion.gToOz(grams))
            } else {
                initialDisplayWeightString = UnitConversion.formatDecimal(grams)
            }
        }
        _servingWeightString = State(initialValue: initialDisplayWeightString)
    }

    var body: some View {
           ZStack {
               VStack(spacing: 0) {
                   customToolbar
                   mainForm
               }
               .alert("Error", isPresented: $showAlert) {
                   Button("OK", role: .cancel) { }.foregroundColor(effectManager.currentGlobalAccentColor)
               } message: { Text(alertMsg) }
               .presentationDetents([.medium, .large])
               .onChange(of: servingWeightString) { _, newText in
                   guard let displayedValue = UnitConversion.parseDecimal(newText) else {
                       if newText.isEmpty { others.weightG?.value = nil }
                       return
                   }
                   let grams = isImperial ? UnitConversion.ozToG(displayedValue) : displayedValue
                   if others.weightG == nil {
                       others.weightG = Nutrient(value: grams, unit: "g")
                   } else if abs((others.weightG?.value ?? 0) - grams) > 0.001 {
                       others.weightG?.value = grams
                   }
               }
               .disabled(isSaving)
               .blur(radius: isSaving ? 1.5 : 0)

               if openMenu != .none {
                   bottomSheetPanel
                       .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
                       .zIndex(1)
               }

               if isSaving {
                   VStack(spacing: 16) {
                       ProgressView()
                           .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                           .scaleEffect(1.5)
                       Text("Saving…")
                           .foregroundStyle(effectManager.currentGlobalAccentColor)
                           .font(.headline)
                   }
                   .padding(30)
                   .glassCardStyle(cornerRadius: 20)
                   .transition(.scale.combined(with: .opacity))
                   .accessibilityLabel("Saving")
                   .zIndex(1000)
               }
           }
           .background(ThemeBackgroundView().ignoresSafeArea())
           .overlay {
               if showAIGenerationToast {
                   aiGenerationToast
               }
               GeometryReader { geometry in
                   Group {
                       if !isSaving &&
                          !showAlert &&
                          GlobalState.aiAvailability != .deviceNotEligible { // ⬅️ НОВО
                           AIButton(geometry: geometry)
                       }
                   }
                   .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
               }
           }
           .onChange(of: name) { _, _ in hasUserMadeEdits = true }
           .onChange(of: itemDescription) { _, _ in hasUserMadeEdits = true }
           .onChange(of: selectedPhoto) { _, _ in hasUserMadeEdits = true }
           .onReceive(NotificationCenter.default.publisher(for: .aiFoodDetailJobCompleted)) { notification in
                      guard !hasUserMadeEdits,
                            let userInfo = notification.userInfo,
                            let completedJobID = userInfo["jobID"] as? UUID,
                            completedJobID == self.runningGenerationJobID else {
                          return
                      }

                      print("▶️ FoodItemEditorView: Received .aiFoodDetailJobCompleted for job \(completedJobID). Populating data.")
                      
               
                      Task {
                          await populateFromCompletedJob(jobID: completedJobID)
                      }
                  }
           .onAppear {
               loadAIButtonPosition()
           }
       }
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Generation Scheduled")
                        .fontWeight(.bold)
                    Text("You'll be notified when your food is ready.")
                        .font(.caption)

                    ProgressView(value: min(max(toastProgress, 0.0), 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .animation(.linear, value: toastProgress)
                }

                Spacer()

                Button("OK") {
                    toastTimer?.invalidate()
                    toastTimer = nil
                    withAnimation {
                        showAIGenerationToast = false
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }
    
    private func populateFromCompletedJob(jobID: UUID) async {
           guard let job = (aiManager.jobs.first { $0.id == jobID }),
                 let resultData = job.resultData else {
               alertMsg = "Could not find completed job data."
               showAlert = true
               runningGenerationJobID = nil
               return
           }

           if #available(iOS 26.0, *) {
               do {
                   let response = try JSONDecoder().decode(FoodItemDTO.self, from: resultData)
                   let generator = AIFoodDetailGenerator(container: ctx.container)
                   let mapped = try generator.mapResponseToState(dto: response, ctx: ctx)

                   withAnimation(.easeInOut) {
                       self.itemDescription    = mapped.description
                       self.minAgeMonthsTxt    = mapped.minAgeMonthsTxt
                       self.selectedCategories = mapped.categories
                       self.selectedAllergens  = mapped.allergens
                       self.macros             = mapped.macros
                       self.others             = mapped.others
                       self.vitamins           = mapped.vitamins
                       self.minerals           = mapped.minerals
                       self.lipids             = mapped.lipids
                       self.aminoAcids         = mapped.aminoAcids
                       self.carbDetails        = mapped.carbDetails
                       self.sterols            = mapped.sterols
                       self.selectedDiets      = mapped.diets

                       if let weightGrams = mapped.others.weightG?.value {
                           let displayValue = isImperial ? UnitConversion.gToOz(weightGrams) : weightGrams
                           self.servingWeightString = GlobalState.formatDecimalString(String(displayValue))
                       } else {
                           self.servingWeightString = ""
                       }
                   }
                   
                   await aiManager.deleteJob(job)
                   runningGenerationJobID = nil

               } catch {
                   alertMsg = "Failed to process AI data: \(error.localizedDescription)"
                   showAlert = true
                   runningGenerationJobID = nil
                   await aiManager.deleteJob(job)
               }
           }
       }
    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            HStack {
                Button("Cancel") { onDismiss(nil) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            Spacer()

            Text(food == nil ? "Add Food" : "Edit Food")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            Spacer()

            let isNameEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty
            let isServingValid = (others.weightG?.value ?? 0) > 0
            let isSaveDisabled = isNameEmpty || !isServingValid || isSaving

            HStack {
                Button(action: save) {
                    HStack(spacing: 8) {
                        Text("Save")
                    }
                }
                .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var mainForm: some View {
          ScrollViewReader { proxy in
              ScrollView(showsIndicators: false) {
                  VStack {
                      basicSection
                      macroSection
                      vitaminSection
                      mineralSection
                      lipidSection
                      aminoAcidsSection
                      carbDetailsSection
                      sterolsSection
                      otherSection
                      
                      Color.clear.frame(height: 150)
                  }
              }
              .onChange(of: focusedField) { _, newFocus in
                  guard let fieldID = newFocus else { return }
                  
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                      withAnimation(.easeInOut(duration: 0.3)) {
                          proxy.scrollTo(fieldID, anchor: .top)
                      }
                  }
              }
              .mask(
                  LinearGradient(
                      gradient: Gradient(stops: [
                          .init(color: .clear, location: 0),
                          .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                          .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                          .init(color: .clear, location: 0.95)
                      ]),
                      startPoint: .top,
                      endPoint: .bottom
                  )
              )
              .background(Color.clear)
          }
      }
    
    // MARK: - Sections
    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(.bottom, -4)

            VStack(spacing: 12) {
                StyledLabeledPicker(label: "Name", isRequired: true) {
                    TextField(
                        "",
                        text: $name,
                        prompt: Text("Blueberries")
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    )
                    .font(.system(size: 16))
                    .focused($focusedField, equals: .name)
                    .disableAutocorrection(true)
                }
                .id(FocusableField.name)

                HStack(spacing: 16) {
                    photoPicker

                    StyledLabeledPicker(label: "Description", height: 120) {
                        descriptionEditor
                            .focused($focusedField, equals: .description)
                    }
                    .id(FocusableField.description)
                }

                // Minimum age
                StyledLabeledPicker(label: "Minimum Age (months)") {
                    ConfigurableTextField(
                        title: "e.g. 6",
                        value: $minAgeMonthsTxt,
                        type: .integer,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        textAlignment: .leading,
                        focused: $focusedField,
                        fieldIdentifier: .minAge
                    )
                    .font(.system(size: 16))
                }
                .id(FocusableField.minAge)

                // Category
                tagPicker(
                    label: "Category",
                    selection: $selectedCategories,
                    items: FoodCategory.allCases.sorted { $0.rawValue < $1.rawValue },
                    itemLabel: { $0.rawValue },
                    menu: .category
                )

                // --- DIETS + WARNING ---
                VStack(alignment: .leading, spacing: 4) {
                    tagPicker(
                        label: "Diets",
                        selection: $selectedDiets,
                        items: allDiets,
                        itemLabel: { $0.name },
                        menu: .diet
                    )

                    if showsDietMismatchWarning {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠️ This food does not match any of the user's diets.")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            if !selectedDietNames.isEmpty {
                                Text("Food diets: \(selectedDietNames)")
                                    .font(.caption2)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }

                            if !userDietNames.isEmpty {
                                Text("User diets: \(userDietNames)")
                                    .font(.caption2)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // --- ALLERGENS + WARNING ---
                VStack(alignment: .leading, spacing: 4) {
                    tagPicker(
                        label: "Allergens",
                        selection: $selectedAllergens,
                        items: Allergen.allCases,
                        itemLabel: { $0.rawValue },
                        menu: .allergen
                    )

                    if !matchingProfileAllergens.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠️ This food contains allergens the user is sensitive to.")
                                .font(.caption)
                                .foregroundStyle(.red)

                            if !foodAllergenNames.isEmpty {
                                Text("Food allergens: \(foodAllergenNames)")
                                    .font(.caption2)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }

                            if !userAllergenNames.isEmpty {
                                Text("User allergens: \(userAllergenNames)")
                                    .font(.caption2)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    }

    // MARK: - Profile Diet & Allergen Helpers

    private var profileDietIDs: Set<Diet.ID> {
        guard let profile else { return [] }
        return Set(profile.diets.map(\.id))
    }

    private var profileAllergenIDs: Set<Allergen.ID> {
        guard let profile else { return [] }
        return Set(profile.allergens.map(\.id))
    }

    private var selectedDietModels: [Diet] {
        allDiets.filter { selectedDiets.contains($0.id) }
    }

    private var selectedDietNames: String {
        let names = selectedDietModels.map(\.name).sorted()
        return names.joined(separator: ", ")
    }

    private var userDietNames: String {
        guard let profile else { return "" }
        let names = profile.diets.map(\.name).sorted()
        return names.joined(separator: ", ")
    }

    private var matchingProfileAllergens: [Allergen] {
        guard !profileAllergenIDs.isEmpty else { return [] }
        return Allergen.allCases.filter { selectedAllergens.contains($0.id) && profileAllergenIDs.contains($0.id) }
    }

    private var foodAllergenNames: String {
        let names = Allergen.allCases
            .filter { selectedAllergens.contains($0.id) }
            .map(\.rawValue)
            .sorted()
        return names.joined(separator: ", ")
    }

    private var userAllergenNames: String {
        guard let profile else { return "" }
        let names = profile.allergens
            .map(\.rawValue)
            .sorted()
        return names.joined(separator: ", ")
    }

    private var showsDietMismatchWarning: Bool {
        // Need both: user has diets AND food has diets
        guard !profileDietIDs.isEmpty else { return false }
        guard !selectedDiets.isEmpty else { return false }
        // Show warning when there is no overlap
        return selectedDiets.isDisjoint(with: profileDietIDs)
    }


    private var photoPicker: some View {
        let imageData = photoData
        let color = effectManager.currentGlobalAccentColor.opacity(0.6)

        return Button {
            showPhotoSourceDialog = true
        } label: {
            Group {
                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "fork.knife.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .confirmationDialog("Select photo source", isPresented: $showPhotoSourceDialog) {
            Button("Take Photo") {
                isShowingCameraPicker = true
            }
            Button("Photo Library") {
                isShowingPhotoLibraryPicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $isShowingCameraPicker) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    photoData = data
                    hasUserMadeEdits = true
                }
            }
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $isShowingPhotoLibraryPicker) {
            PhotoLibraryPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    photoData = data
                    hasUserMadeEdits = true
                }
            }
            .presentationCornerRadius(20)
        }
    }

    private var descriptionEditor: some View {
            ZStack(alignment: .topLeading) {
                if itemDescription.isEmpty {
                    Text("Description")
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                        .font(.system(size: 16))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $itemDescription).font(.system(size: 16))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
        }
        
        private var macroSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Macronutrients", isExpanded: $showMacros)
                if showMacros {
                    VStack(spacing: 12) {
                        macroGrid
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .padding(.top, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var vitaminSection: some View {
            let allRowsWithFocus = vitaminRows()
            let allRows = allRowsWithFocus.map(\.row)
            let priority = Set(profile?.priorityVitamins.map(label(for:)) ?? [])
            let (prioRows, _) = splitRows(allRows, priorityNames: priority)

            let prioLabels = Set(prioRows.map(\.label))
            let prio = allRowsWithFocus.filter { prioLabels.contains($0.row.label) }
            let other = allRowsWithFocus.filter { !prioLabels.contains($0.row.label) }

            return VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Vitamins", isExpanded: $showMoreVitamins, hasOtherItems: !other.isEmpty)
                
                if !prio.isEmpty || (showMoreVitamins && !other.isEmpty) {
                   VStack(spacing: 12) {
                       ForEach(prio, id: \.row.label) { item in
                           FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                       }
                       .foregroundStyle(effectManager.currentGlobalAccentColor)
                       
                       if showMoreVitamins {
                           ForEach(other, id: \.row.label) { item in
                               FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                           }
                           .foregroundStyle(effectManager.currentGlobalAccentColor)
                       }
                   }
                   .padding()
                   .glassCardStyle(cornerRadius: 20)
                   .padding(.top, 4)
               }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var mineralSection: some View {
            let allRowsWithFocus = mineralRows()
            let allRows = allRowsWithFocus.map(\.row)
            let priority = Set(profile?.priorityMinerals.map(label(for:)) ?? [])
            let (prioRows, otherRows) = splitRows(allRows, priorityNames: priority)

            let prioLabels = Set(prioRows.map(\.label))
            let prio = allRowsWithFocus.filter { prioLabels.contains($0.row.label) }
            let other = allRowsWithFocus.filter { !prioLabels.contains($0.row.label) }
            
            return VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Minerals", isExpanded: $showMoreMinerals, hasOtherItems: !other.isEmpty)
                
                if !prio.isEmpty || (showMoreMinerals && !other.isEmpty) {
                   VStack(spacing: 12) {
                       ForEach(prio, id: \.row.label) { item in
                           FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                       }
                       .foregroundStyle(effectManager.currentGlobalAccentColor)
                       
                       if showMoreMinerals {
                           ForEach(other, id: \.row.label) { item in
                               FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                           }
                           .foregroundStyle(effectManager.currentGlobalAccentColor)
                       }
                   }
                   .padding()
                   .glassCardStyle(cornerRadius: 20)
                   .padding(.top, 4)
               }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var lipidSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Lipids", isExpanded: $showLipids)
                
                if showLipids {
                    VStack(spacing: 12) {
                        lipidTotalsGrid.foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)

                    VStack(spacing: 12) {
                        lipidSFAGrid.foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)

                    VStack(spacing: 12) {
                        lipidMUFAGrid.foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)

                    VStack(spacing: 12) {
                        lipidTFAGrid.foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)

                    VStack(spacing: 12) {
                        lipidPUFAGrid.foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var aminoAcidsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Amino Acids", isExpanded: $showAminoAcids)
                if showAminoAcids {
                    VStack(spacing: 12) {
                        ForEach(aminoAcidRows(), id: \.row.label) { item in
                            FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                        }
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var carbDetailsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Carbohydrate Details", isExpanded: $showCarbDetails)
                if showCarbDetails {
                    VStack(spacing: 12) {
                        ForEach(carbDetailRows(), id: \.row.label) { item in
                            FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                        }
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var sterolsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader("Sterols", isExpanded: $showSterols)
                if showSterols {
                    VStack(spacing: 12) {
                        ForEach(sterolRows(), id: \.row.label) { item in
                            FocusableNutrientRow(row: item.row, focusState: $focusedField, focusID: item.focusID)
                        }
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }.padding().glassCardStyle(cornerRadius: 20).padding(.top, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        private var otherSection: some View {
           VStack(alignment: .leading, spacing: 8) {
               collapsibleHeader("Other", isExpanded: $showOther)
               if showOther {
                   VStack(spacing: 12) { otherGrid }
                       .padding()
                       .glassCardStyle(cornerRadius: 20)
                       .padding(.top, 4)
               }
           }
           .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
       }
    
    // MARK: - Save Logic
    private func save() {
        let totalWeight: Double = others.weightG?.value ?? 0
        guard totalWeight > 0 else {
            alertMsg = "Please enter the Weight / serving (\(servingUnit))."
            showAlert = true
            return
        }
        
        let carbs: Double   = macros.carbohydrates?.value ?? 0
        let protein: Double = macros.protein?.value ?? 0
        let fat: Double     = macros.fat?.value ?? 0
        let macroSum = carbs + protein + fat
        
        if macroSum > totalWeight {
            alertMsg = String(
                format: "The sum of carbohydrates, protein, and fat (%.1f g) cannot exceed the total serving weight (%.1f g).",
                macroSum, totalWeight
            )
            showAlert = true
            return
        }
        
        Task { @MainActor in
            isSaving = true
            await Task.yield()
            defer { isSaving = false }
            
            let item: FoodItem = food ?? {
                let nextID = (try? ctx.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
                let new = FoodItem(id: nextID + 1, name: name, isUserAdded: true)
                ctx.insert(new)
                return new
            }()
            
            // Тук се присвоява новото име
            item.name = name
            
            // ... (другите присвоявания на свойства остават същите) ...
            item.photo = photoData
            item.category = idsToEnums(selectedCategories, of: FoodCategory.self)
            
            let chosenDiets = allDiets.filter { selectedDiets.contains($0.id) }
            item.diets = chosenDiets.isEmpty ? nil : chosenDiets
            
            item.allergens = idsToEnums(selectedAllergens, of: Allergen.self)
            item.itemDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            item.minAgeMonths = Int(minAgeMonthsTxt) ?? 0
            
            item.macronutrients = MacronutrientsData(from: macros)
            item.lipids         = LipidsData(from: lipids)
            item.vitamins       = VitaminsData(from: vitamins)
            item.minerals       = MineralsData(from: minerals)
            item.other          = OtherCompoundsData(from: others)
            item.aminoAcids     = AminoAcidsData(from: aminoAcids)
            item.carbDetails    = CarbDetailsData(from: carbDetails)
            item.sterols        = SterolsData(from: sterols)
            
            item.macronutrients?.foodItem = item
            item.lipids?.foodItem         = item
            item.vitamins?.foodItem       = item
            item.minerals?.foodItem       = item
            item.other?.foodItem          = item
            item.aminoAcids?.foodItem     = item
            item.carbDetails?.foodItem    = item
            item.sterols?.foodItem        = item
            
            do {
                try ctx.save()
                
                // Тези два реда са ключови и трябва да са СЛЕД ctx.save()
                SearchIndexStore.shared.updateItem(item, context: ctx)
                
                onDismiss(item)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == "NSSQLiteErrorDomain", nsErr.code == 11 {
                    alertMsg = "Your local database appears to be corrupted (SQLite code 11)."
                } else {
                    alertMsg = nsErr.localizedDescription
                }
                showAlert = true
            }
        }
    }

    // MARK: - Helper Views & Functions
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private func collapsibleHeader(_ title: String, isExpanded: Binding<Bool>, hasOtherItems: Bool = true) -> some View {
        Button(action: { withAnimation { isExpanded.wrappedValue.toggle() } }) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                Spacer()
                if hasOtherItems {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasOtherItems)
    }
    
    private func nutrientGrid(_ rows: [NutrientRow]) -> some View {
        ForEach(rows.indices, id: \.self) { i in
            let row = rows[i]
            HStack {
                Text(row.label)
                Spacer()
                HStack(spacing: 4) {
                    ConfigurableTextField(
                        title: "0",
                        value: row.field,
                        type: .decimal,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6)
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: row.field.wrappedValue) { _, newValue in
                        if let number = GlobalState.double(from: newValue), number > 100000 {
                            row.field.wrappedValue = "100000"
                        }
                    }
                    Text(row.unit).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
        }
    }
    
    private var macroGrid: some View {
           VStack(spacing: 12) {
               FocusableNutrientRow(
                   row: .init(label: "Energy", unit: "kcal", field: nutBinding(\.energyKcal, state: $others, unit: "kcal")),
                   focusState: $focusedField,
                   focusID: .energyKcal
               )
               
               HStack {
                   Text("Weight / serving")
                   Text("*").foregroundStyle(.red)
                   Spacer()
                   HStack(spacing: 4) {
                       ConfigurableTextField(
                           title: "0",
                           value: $servingWeightString,
                           type: .decimal,
                           placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                           focused: $focusedField,
                           fieldIdentifier: .servingWeight
                       )
                       .multilineTextAlignment(.trailing)
                       .frame(width: 100)
                       .onChange(of: servingWeightString) { _, newValue in
                           if let number = GlobalState.double(from: newValue), number > 100000 {
                               let gramsInModel = isImperial ? UnitConversion.ozToG(100000) : 100000
                               others.weightG?.value = gramsInModel
                               servingWeightString = "100000"
                           }
                       }
                       Text(servingUnit).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                   }
               }
               .id(FocusableField.servingWeight) // ID на контейнера
               
               FocusableNutrientRow(row: .init(label: "Carbs", unit: "g", field: nutBinding(\.carbohydrates, state: $macros, unit: "g")), focusState: $focusedField, focusID: .carbohydrates)
               FocusableNutrientRow(row: .init(label: "Protein", unit: "g", field: nutBinding(\.protein, state: $macros, unit: "g")), focusState: $focusedField, focusID: .protein)
               FocusableNutrientRow(row: .init(label: "Fat", unit: "g", field: nutBinding(\.fat, state: $macros, unit: "g")), focusState: $focusedField, focusID: .fat)
           }
       }
    
    private var lipidTotalsGrid: some View {
        VStack(spacing: 12) {
            Text("Totals")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            // Заменяме nutrientGrid с VStack от FocusableNutrientRow
            VStack(spacing: 12) { // Добавяме VStack за консистентно разстояние
                FocusableNutrientRow(
                    row: .init(label: "Sat. fat", unit: "g", field: nutBinding(\.totalSaturated, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalSaturated
                )
                FocusableNutrientRow(
                    row: .init(label: "Mono-unsat.", unit: "g", field: nutBinding(\.totalMonounsaturated, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalMonounsaturated
                )
                FocusableNutrientRow(
                    row: .init(label: "Poly-unsat.", unit: "g", field: nutBinding(\.totalPolyunsaturated, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalPolyunsaturated
                )
                FocusableNutrientRow(
                    row: .init(label: "Trans fat", unit: "g", field: nutBinding(\.totalTrans, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalTrans
                )
                FocusableNutrientRow(
                    row: .init(label: "Trans monoenoic", unit: "g", field: nutBinding(\.totalTransMonoenoic, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalTransMonoenoic
                )
                FocusableNutrientRow(
                    row: .init(label: "Trans polyenoic", unit: "g", field: nutBinding(\.totalTransPolyenoic, state: $lipids)),
                    focusState: $focusedField,
                    focusID: .totalTransPolyenoic
                )
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
    }
    
    private var lipidSFAGrid: some View {
        VStack(spacing: 8) {
            Text("Saturated Fatty Acids (SFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            VStack(spacing: 12) { // Добавяме VStack за консистентно разстояние
                FocusableNutrientRow(row: .init(label: "C4:0",  unit: "g", field: nutBinding(\.sfa4_0,  state: $lipids)), focusState: $focusedField, focusID: .sfa4_0)
                FocusableNutrientRow(row: .init(label: "C6:0",  unit: "g", field: nutBinding(\.sfa6_0,  state: $lipids)), focusState: $focusedField, focusID: .sfa6_0)
                FocusableNutrientRow(row: .init(label: "C8:0",  unit: "g", field: nutBinding(\.sfa8_0,  state: $lipids)), focusState: $focusedField, focusID: .sfa8_0)
                FocusableNutrientRow(row: .init(label: "C10:0", unit: "g", field: nutBinding(\.sfa10_0, state: $lipids)), focusState: $focusedField, focusID: .sfa10_0)
                FocusableNutrientRow(row: .init(label: "C12:0", unit: "g", field: nutBinding(\.sfa12_0, state: $lipids)), focusState: $focusedField, focusID: .sfa12_0)
                FocusableNutrientRow(row: .init(label: "C13:0", unit: "g", field: nutBinding(\.sfa13_0, state: $lipids)), focusState: $focusedField, focusID: .sfa13_0)
                FocusableNutrientRow(row: .init(label: "C14:0", unit: "g", field: nutBinding(\.sfa14_0, state: $lipids)), focusState: $focusedField, focusID: .sfa14_0)
                FocusableNutrientRow(row: .init(label: "C15:0", unit: "g", field: nutBinding(\.sfa15_0, state: $lipids)), focusState: $focusedField, focusID: .sfa15_0)
                FocusableNutrientRow(row: .init(label: "C16:0", unit: "g", field: nutBinding(\.sfa16_0, state: $lipids)), focusState: $focusedField, focusID: .sfa16_0)
                FocusableNutrientRow(row: .init(label: "C17:0", unit: "g", field: nutBinding(\.sfa17_0, state: $lipids)), focusState: $focusedField, focusID: .sfa17_0)
                FocusableNutrientRow(row: .init(label: "C18:0", unit: "g", field: nutBinding(\.sfa18_0, state: $lipids)), focusState: $focusedField, focusID: .sfa18_0)
                FocusableNutrientRow(row: .init(label: "C20:0", unit: "g", field: nutBinding(\.sfa20_0, state: $lipids)), focusState: $focusedField, focusID: .sfa20_0)
                FocusableNutrientRow(row: .init(label: "C22:0", unit: "g", field: nutBinding(\.sfa22_0, state: $lipids)), focusState: $focusedField, focusID: .sfa22_0)
                FocusableNutrientRow(row: .init(label: "C24:0", unit: "g", field: nutBinding(\.sfa24_0, state: $lipids)), focusState: $focusedField, focusID: .sfa24_0)
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
    }

    private var lipidMUFAGrid: some View {
        VStack(spacing: 8) {
            Text("Monounsaturated Fatty Acids (MUFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            // --- НАЧАЛО НА ПРОМЯНАТА ---
            VStack(spacing: 12) {
                FocusableNutrientRow(row: .init(label: "C14:1", unit: "g", field: nutBinding(\.mufa14_1, state: $lipids)), focusState: $focusedField, focusID: .mufa14_1)
                FocusableNutrientRow(row: .init(label: "C15:1", unit: "g", field: nutBinding(\.mufa15_1, state: $lipids)), focusState: $focusedField, focusID: .mufa15_1)
                FocusableNutrientRow(row: .init(label: "C16:1", unit: "g", field: nutBinding(\.mufa16_1, state: $lipids)), focusState: $focusedField, focusID: .mufa16_1)
                FocusableNutrientRow(row: .init(label: "C17:1", unit: "g", field: nutBinding(\.mufa17_1, state: $lipids)), focusState: $focusedField, focusID: .mufa17_1)
                FocusableNutrientRow(row: .init(label: "C18:1", unit: "g", field: nutBinding(\.mufa18_1, state: $lipids)), focusState: $focusedField, focusID: .mufa18_1)
                FocusableNutrientRow(row: .init(label: "C20:1", unit: "g", field: nutBinding(\.mufa20_1, state: $lipids)), focusState: $focusedField, focusID: .mufa20_1)
                FocusableNutrientRow(row: .init(label: "C22:1", unit: "g", field: nutBinding(\.mufa22_1, state: $lipids)), focusState: $focusedField, focusID: .mufa22_1)
                FocusableNutrientRow(row: .init(label: "C24:1", unit: "g", field: nutBinding(\.mufa24_1, state: $lipids)), focusState: $focusedField, focusID: .mufa24_1)
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
    }

    private var lipidTFAGrid: some View {
        VStack(spacing: 8) {
            Text("Trans Fatty Acids (TFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            // --- НАЧАЛО НА ПРОМЯНАТА ---
            VStack(spacing: 12) {
                FocusableNutrientRow(row: .init(label: "C16:1 t", unit: "g", field: nutBinding(\.tfa16_1_t, state: $lipids)), focusState: $focusedField, focusID: .tfa16_1_t)
                FocusableNutrientRow(row: .init(label: "C18:1 t", unit: "g", field: nutBinding(\.tfa18_1_t, state: $lipids)), focusState: $focusedField, focusID: .tfa18_1_t)
                FocusableNutrientRow(row: .init(label: "C22:1 t", unit: "g", field: nutBinding(\.tfa22_1_t, state: $lipids)), focusState: $focusedField, focusID: .tfa22_1_t)
                FocusableNutrientRow(row: .init(label: "C18:2 t", unit: "g", field: nutBinding(\.tfa18_2_t, state: $lipids)), focusState: $focusedField, focusID: .tfa18_2_t)
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
    }

    private var lipidPUFAGrid: some View {
        VStack(spacing: 8) {
            Text("Polyunsaturated Fatty Acids (PUFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            // --- НАЧАЛО НА ПРОМЯНАТА ---
            VStack(spacing: 12) {
                FocusableNutrientRow(row: .init(label: "C18:2", unit: "g", field: nutBinding(\.pufa18_2, state: $lipids)), focusState: $focusedField, focusID: .pufa18_2)
                FocusableNutrientRow(row: .init(label: "C18:3", unit: "g", field: nutBinding(\.pufa18_3, state: $lipids)), focusState: $focusedField, focusID: .pufa18_3)
                FocusableNutrientRow(row: .init(label: "C18:4", unit: "g", field: nutBinding(\.pufa18_4, state: $lipids)), focusState: $focusedField, focusID: .pufa18_4)
                FocusableNutrientRow(row: .init(label: "C20:2", unit: "g", field: nutBinding(\.pufa20_2, state: $lipids)), focusState: $focusedField, focusID: .pufa20_2)
                FocusableNutrientRow(row: .init(label: "C20:3", unit: "g", field: nutBinding(\.pufa20_3, state: $lipids)), focusState: $focusedField, focusID: .pufa20_3)
                FocusableNutrientRow(row: .init(label: "C20:4", unit: "g", field: nutBinding(\.pufa20_4, state: $lipids)), focusState: $focusedField, focusID: .pufa20_4)
                FocusableNutrientRow(row: .init(label: "C20:5", unit: "g", field: nutBinding(\.pufa20_5, state: $lipids)), focusState: $focusedField, focusID: .pufa20_5)
                FocusableNutrientRow(row: .init(label: "C21:5", unit: "g", field: nutBinding(\.pufa21_5, state: $lipids)), focusState: $focusedField, focusID: .pufa21_5)
                FocusableNutrientRow(row: .init(label: "C22:4", unit: "g", field: nutBinding(\.pufa22_4, state: $lipids)), focusState: $focusedField, focusID: .pufa22_4)
                FocusableNutrientRow(row: .init(label: "C22:5", unit: "g", field: nutBinding(\.pufa22_5, state: $lipids)), focusState: $focusedField, focusID: .pufa22_5)
                FocusableNutrientRow(row: .init(label: "C22:6", unit: "g", field: nutBinding(\.pufa22_6, state: $lipids)), focusState: $focusedField, focusID: .pufa22_6)
                FocusableNutrientRow(row: .init(label: "C2:4",  unit: "g", field: nutBinding(\.pufa2_4,  state: $lipids)), focusState: $focusedField, focusID: .pufa2_4)
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
    }

    private var otherGrid: some View {
          VStack(spacing: 12) {
              FocusableNutrientRow(row: .init(label: "Alcohol", unit: "g", field: nutBinding(\.alcoholEthyl, state: $others, unit: "g")), focusState: $focusedField, focusID: .alcoholEthyl)
              FocusableNutrientRow(row: .init(label: "Caffeine", unit: "mg", field: nutBinding(\.caffeine, state: $others, unit: "mg")), focusState: $focusedField, focusID: .caffeine)
              FocusableNutrientRow(row: .init(label: "Theobromine", unit: "mg", field: nutBinding(\.theobromine, state: $others, unit: "mg")), focusState: $focusedField, focusID: .theobromine)
              FocusableNutrientRow(row: .init(label: "Cholesterol", unit: "mg", field: nutBinding(\.cholesterol, state: $others, unit: "mg")), focusState: $focusedField, focusID: .cholesterol)
              FocusableNutrientRow(row: .init(label: "Water", unit: "g", field: nutBinding(\.water, state: $others, unit: "g")), focusState: $focusedField, focusID: .water)
              FocusableNutrientRow(row: .init(label: "Ash", unit: "g", field: nutBinding(\.ash, state: $others, unit: "g")), focusState: $focusedField, focusID: .ash)
              FocusableNutrientRow(row: .init(label: "Betaine", unit: "mg", field: nutBinding(\.betaine, state: $others, unit: "mg")), focusState: $focusedField, focusID: .betaine)
              FocusableNutrientRow(row: .init(label: "Fiber", unit: "g", field: nutBinding(\.fiber, state: $macros, unit: "g")), focusState: $focusedField, focusID: .fiber)
              FocusableNutrientRow(row: .init(label: "Total sugars", unit: "g", field: nutBinding(\.totalSugars, state: $macros, unit: "g")), focusState: $focusedField, focusID: .totalSugars)
              FocusableNutrientRow(row: .init(label: "pH", unit: "", field: nutBinding(\.alkalinityPH, state: $others, unit: "pH")), focusState: $focusedField, focusID: .alkalinityPH)
          }
      }
  
    
    private func splitRows(_ rows: [NutrientRow], priorityNames: Set<String>) -> (prio: [NutrientRow], other: [NutrientRow]) {
        (rows.filter { priorityNames.contains($0.label) },
         rows.filter { !priorityNames.contains($0.label) })
    }
    
    private func label(for vitamin: Vitamin) -> String { vitaminLabelById[vitamin.id] ?? vitamin.name }
    private func label(for mineral: Mineral) -> String { mineralLabelById[mineral.id] ?? mineral.name }
    
    private func vitaminRows() -> [(row: NutrientRow, focusID: FocusableField)] {
        return [
            (row: .init(label: "Vit A", unit: "µg RAE", field: nutBinding(\.vitaminA_RAE, state: $vitamins, unit: "µg")), focusID: .vitaminA_RAE),
            (row: .init(label: "Retinol", unit: "µg", field: nutBinding(\.retinol, state: $vitamins, unit: "µg")), focusID: .retinol),
            (row: .init(label: "α-Carotene", unit: "µg", field: nutBinding(\.caroteneAlpha, state: $vitamins, unit: "µg")), focusID: .caroteneAlpha),
            (row: .init(label: "β-Carotene", unit: "µg", field: nutBinding(\.caroteneBeta, state: $vitamins, unit: "µg")), focusID: .caroteneBeta),
            (row: .init(label: "β-Cryptoxanthin", unit: "µg", field: nutBinding(\.cryptoxanthinBeta, state: $vitamins, unit: "µg")), focusID: .cryptoxanthinBeta),
            (row: .init(label: "Lutein + Zeax.", unit: "µg", field: nutBinding(\.luteinZeaxanthin, state: $vitamins, unit: "µg")), focusID: .luteinZeaxanthin),
            (row: .init(label: "Lycopene", unit: "µg", field: nutBinding(\.lycopene, state: $vitamins, unit: "µg")), focusID: .lycopene),
            (row: .init(label: "B1 Thiamin", unit: "mg", field: nutBinding(\.vitaminB1_Thiamin, state: $vitamins, unit: "mg")), focusID: .vitaminB1_Thiamin),
            (row: .init(label: "B2 Riboflavin", unit: "mg", field: nutBinding(\.vitaminB2_Riboflavin, state: $vitamins, unit: "mg")), focusID: .vitaminB2_Riboflavin),
            (row: .init(label: "B3 Niacin", unit: "mg", field: nutBinding(\.vitaminB3_Niacin, state: $vitamins, unit: "mg")), focusID: .vitaminB3_Niacin),
            (row: .init(label: "B5 Pant. acid", unit: "mg", field: nutBinding(\.vitaminB5_PantothenicAcid, state: $vitamins, unit: "mg")), focusID: .vitaminB5_PantothenicAcid),
            (row: .init(label: "B6", unit: "mg", field: nutBinding(\.vitaminB6, state: $vitamins, unit: "mg")), focusID: .vitaminB6),
            (row: .init(label: "Folate DFE", unit: "µg", field: nutBinding(\.folateDFE, state: $vitamins, unit: "µg")), focusID: .folateDFE),
            (row: .init(label: "Folate food", unit: "µg", field: nutBinding(\.folateFood, state: $vitamins, unit: "µg")), focusID: .folateFood),
            (row: .init(label: "Folate total", unit: "µg", field: nutBinding(\.folateTotal, state: $vitamins, unit: "µg")), focusID: .folateTotal),
            (row: .init(label: "Folic acid", unit: "µg", field: nutBinding(\.folicAcid, state: $vitamins, unit: "µg")), focusID: .folicAcid),
            (row: .init(label: "B12", unit: "µg", field: nutBinding(\.vitaminB12, state: $vitamins, unit: "µg")), focusID: .vitaminB12),
            (row: .init(label: "Vit C", unit: "mg", field: nutBinding(\.vitaminC, state: $vitamins, unit: "mg")), focusID: .vitaminC),
            (row: .init(label: "Vit D", unit: "µg", field: nutBinding(\.vitaminD, state: $vitamins, unit: "µg")), focusID: .vitaminD),
            (row: .init(label: "Vit E", unit: "mg", field: nutBinding(\.vitaminE, state: $vitamins, unit: "mg")), focusID: .vitaminE),
            (row: .init(label: "Vit K", unit: "µg", field: nutBinding(\.vitaminK, state: $vitamins, unit: "µg")), focusID: .vitaminK),
            (row: .init(label: "Choline", unit: "mg", field: nutBinding(\.choline, state: $vitamins, unit: "mg")), focusID: .choline)
        ]
    }

    private func mineralRows() -> [(row: NutrientRow, focusID: FocusableField)] {
        return [
            (row: .init(label: "Calcium", unit: "mg", field: nutBinding(\.calcium, state: $minerals, unit: "mg")), focusID: .calcium),
            (row: .init(label: "Phosphorus", unit: "mg", field: nutBinding(\.phosphorus, state: $minerals, unit: "mg")), focusID: .phosphorus),
            (row: .init(label: "Magnesium", unit: "mg", field: nutBinding(\.magnesium, state: $minerals, unit: "mg")), focusID: .magnesium),
            (row: .init(label: "Potassium", unit: "mg", field: nutBinding(\.potassium, state: $minerals, unit: "mg")), focusID: .potassium),
            (row: .init(label: "Sodium", unit: "mg", field: nutBinding(\.sodium, state: $minerals, unit: "mg")), focusID: .sodium),
            (row: .init(label: "Iron", unit: "mg", field: nutBinding(\.iron, state: $minerals, unit: "mg")), focusID: .iron),
            (row: .init(label: "Zinc", unit: "mg", field: nutBinding(\.zinc, state: $minerals, unit: "mg")), focusID: .zinc),
            (row: .init(label: "Copper", unit: "mg", field: nutBinding(\.copper, state: $minerals, unit: "mg")), focusID: .copper),
            (row: .init(label: "Manganese", unit: "mg", field: nutBinding(\.manganese, state: $minerals, unit: "mg")), focusID: .manganese),
            (row: .init(label: "Selenium", unit: "µg", field: nutBinding(\.selenium, state: $minerals, unit: "µg")), focusID: .selenium),
            (row: .init(label: "Fluoride", unit: "µg", field: nutBinding(\.fluoride, state: $minerals, unit: "µg")), focusID: .fluoride)
        ]
    }
    
    private func aminoAcidRows() -> [(row: NutrientRow, focusID: FocusableField)] {
        return [
            (row: .init(label: "Alanine", unit: "g", field: nutBinding(\.alanine, state: $aminoAcids)), focusID: .alanine),
            (row: .init(label: "Arginine", unit: "g", field: nutBinding(\.arginine, state: $aminoAcids)), focusID: .arginine),
            (row: .init(label: "Aspartic Acid", unit: "g", field: nutBinding(\.asparticAcid, state: $aminoAcids)), focusID: .asparticAcid),
            (row: .init(label: "Cystine", unit: "g", field: nutBinding(\.cystine, state: $aminoAcids)), focusID: .cystine),
            (row: .init(label: "Glutamic Acid", unit: "g", field: nutBinding(\.glutamicAcid, state: $aminoAcids)), focusID: .glutamicAcid),
            (row: .init(label: "Glycine", unit: "g", field: nutBinding(\.glycine, state: $aminoAcids)), focusID: .glycine),
            (row: .init(label: "Histidine", unit: "g", field: nutBinding(\.histidine, state: $aminoAcids)), focusID: .histidine),
            (row: .init(label: "Isoleucine", unit: "g", field: nutBinding(\.isoleucine, state: $aminoAcids)), focusID: .isoleucine),
            (row: .init(label: "Leucine", unit: "g", field: nutBinding(\.leucine, state: $aminoAcids)), focusID: .leucine),
            (row: .init(label: "Lysine", unit: "g", field: nutBinding(\.lysine, state: $aminoAcids)), focusID: .lysine),
            (row: .init(label: "Methionine", unit: "g", field: nutBinding(\.methionine, state: $aminoAcids)), focusID: .methionine),
            (row: .init(label: "Phenylalanine", unit: "g", field: nutBinding(\.phenylalanine, state: $aminoAcids)), focusID: .phenylalanine),
            (row: .init(label: "Proline", unit: "g", field: nutBinding(\.proline, state: $aminoAcids)), focusID: .proline),
            (row: .init(label: "Threonine", unit: "g", field: nutBinding(\.threonine, state: $aminoAcids)), focusID: .threonine),
            (row: .init(label: "Tryptophan", unit: "g", field: nutBinding(\.tryptophan, state: $aminoAcids)), focusID: .tryptophan),
            (row: .init(label: "Tyrosine", unit: "g", field: nutBinding(\.tyrosine, state: $aminoAcids)), focusID: .tyrosine),
            (row: .init(label: "Valine", unit: "g", field: nutBinding(\.valine, state: $aminoAcids)), focusID: .valine),
            (row: .init(label: "Serine", unit: "g", field: nutBinding(\.serine, state: $aminoAcids)), focusID: .serine),
            (row: .init(label: "Hydroxyproline", unit: "g", field: nutBinding(\.hydroxyproline, state: $aminoAcids)), focusID: .hydroxyproline)
        ]
    }
    
    private func carbDetailRows() -> [(row: NutrientRow, focusID: FocusableField)] {
        return [
            (row: .init(label: "Starch", unit: "g", field: nutBinding(\.starch, state: $carbDetails)), focusID: .starch),
            (row: .init(label: "Sucrose", unit: "g", field: nutBinding(\.sucrose, state: $carbDetails)), focusID: .sucrose),
            (row: .init(label: "Glucose", unit: "g", field: nutBinding(\.glucose, state: $carbDetails)), focusID: .glucose),
            (row: .init(label: "Fructose", unit: "g", field: nutBinding(\.fructose, state: $carbDetails)), focusID: .fructose),
            (row: .init(label: "Lactose", unit: "g", field: nutBinding(\.lactose, state: $carbDetails)), focusID: .lactose),
            (row: .init(label: "Maltose", unit: "g", field: nutBinding(\.maltose, state: $carbDetails)), focusID: .maltose),
            (row: .init(label: "Galactose", unit: "g", field: nutBinding(\.galactose, state: $carbDetails)), focusID: .galactose)
        ]
    }
    
    private func sterolRows() -> [(row: NutrientRow, focusID: FocusableField)] {
        return [
            (row: .init(label: "Phytosterols", unit: "mg", field: nutBinding(\.phytosterols, state: $sterols, unit: "mg")), focusID: .phytosterols),
            (row: .init(label: "Beta-Sitosterol", unit: "mg", field: nutBinding(\.betaSitosterol, state: $sterols, unit: "mg")), focusID: .betaSitosterol),
            (row: .init(label: "Campesterol", unit: "mg", field: nutBinding(\.campesterol, state: $sterols, unit: "mg")), focusID: .campesterol),
            (row: .init(label: "Stigmasterol", unit: "mg", field: nutBinding(\.stigmasterol, state: $sterols, unit: "mg")), focusID: .stigmasterol)
        ]
    }

    private func idsToEnums<E: CaseIterable & Identifiable>(_ ids: Set<E.ID>, of _: E.Type) -> [E]? where E.ID == String {
        let all = E.allCases as! [E]
        let filtered = all.filter { ids.contains($0.id) }
        return filtered.isEmpty ? nil : filtered
    }
        
    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
           
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            openMenu = .none
                        }
                    }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            openMenu = .none
                        }
                    }
            }
            
            VStack(spacing: 8) {
                ZStack {
                    HStack {
                        Text("Select \(openMenu.title)")
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        
                        Spacer()
                        
                        Button("Done") {
                            hideKeyboard()
                            withAnimation { openMenu = .none }
                        }
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)
                    }
                }
                .padding(.horizontal)
                .frame(height: 35)
                    
                dropDownLayer
                
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
    }
    
    @ViewBuilder
    private var dropDownLayer: some View {
        Group {
            switch openMenu {
            case .category:
                dropdownMenu(selection: $selectedCategories, items: FoodCategory.allCases.sorted { $0.rawValue < $1.rawValue }, label: { $0.rawValue })
            case .diet:
                // --- CORRECTION: Use `allDiets` from query ---
                dropdownMenu(selection: $selectedDiets, items: allDiets, label: { $0.name })
            case .allergen:
                dropdownMenu(selection: $selectedAllergens, items: Allergen.allCases, label: { $0.rawValue })
            case .none:
                EmptyView()
            }
        }
    }

    private func dropdownMenu<I: Identifiable & Hashable>(
        selection: Binding<Set<I.ID>>,
        items: [I],
        label: @escaping (I) -> String,
        selectAllBtn: Bool = false
    ) -> some View {
        DropdownMenu(selection: selection,
                     items: items,
                     label: label,
                     selectAllBtn: selectAllBtn)
    }

    @ViewBuilder
    private func tagPicker<I: Identifiable & Hashable>(
        label: String,
        selection: Binding<Set<I.ID>>,
        items: [I],
        itemLabel: @escaping (I) -> String,
        menu: OpenMenu
    ) -> some View {
        StyledLabeledPicker(label: label, isFixedHeight: false) {
            MultiSelectButton(
                selection: selection,
                items: items,
                label: itemLabel,
                prompt: "Select \(label)",
                isExpanded: openMenu == menu
            )
            .contentShape(Rectangle())
            .onTapGesture {
                   withAnimation(.easeInOut(duration: 0.25)) {
                       openMenu = menu
                   }
               }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .font(.system(size: 16))
        }
    }
    
    private func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            alertMsg = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMsg = "Apple Intelligence is turned off. Enable it in Settings to use AI."
        case .modelNotReady:
            alertMsg = "The model is downloading or preparing. Please try again shortly."
        case .unavailableUnsupportedOS:
            alertMsg = "Apple Intelligence requires iOS 26 or newer."
        case .unavailableOther:
            alertMsg = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }

}

// Unchanged helper extensions
extension FoodItemEditorView {
    fileprivate func MacronutrientsData(from form: MacroForm) -> MacronutrientsData { .init(carbohydrates: form.carbohydrates, protein: form.protein, fat: form.fat, fiber: form.fiber, totalSugars: form.totalSugars) }
    fileprivate func LipidsData(from form: LipidForm) -> LipidsData {
            .init(
                totalSaturated: form.totalSaturated,
                totalMonounsaturated: form.totalMonounsaturated,
                totalPolyunsaturated: form.totalPolyunsaturated,
                totalTrans: form.totalTrans,
                totalTransMonoenoic: form.totalTransMonoenoic,
                totalTransPolyenoic: form.totalTransPolyenoic,
                sfa4_0: form.sfa4_0, sfa6_0: form.sfa6_0, sfa8_0: form.sfa8_0,
                sfa10_0: form.sfa10_0, sfa12_0: form.sfa12_0, sfa13_0: form.sfa13_0,
                sfa14_0: form.sfa14_0, sfa15_0: form.sfa15_0, sfa16_0: form.sfa16_0,
                sfa17_0: form.sfa17_0, sfa18_0: form.sfa18_0, sfa20_0: form.sfa20_0,
                sfa22_0: form.sfa22_0, sfa24_0: form.sfa24_0,
                mufa14_1: form.mufa14_1, mufa15_1: form.mufa15_1, mufa16_1: form.mufa16_1,
                mufa17_1: form.mufa17_1, mufa18_1: form.mufa18_1, mufa20_1: form.mufa20_1,
                mufa22_1: form.mufa22_1, mufa24_1: form.mufa24_1,
                tfa16_1_t: form.tfa16_1_t, tfa18_1_t: form.tfa18_1_t, tfa22_1_t: form.tfa22_1_t,
                tfa18_2_t: form.tfa18_2_t,
                pufa18_2: form.pufa18_2, pufa18_3: form.pufa18_3, pufa18_4: form.pufa18_4,
                pufa20_2: form.pufa20_2, pufa20_3: form.pufa20_3, pufa20_4: form.pufa20_4,
                pufa20_5: form.pufa20_5, pufa21_5: form.pufa21_5, pufa22_4: form.pufa22_4,
                pufa22_5: form.pufa22_5, pufa22_6: form.pufa22_6, pufa2_4: form.pufa2_4
            )
        }
    fileprivate func VitaminsData(from form: VitaminForm) -> VitaminsData { .init(vitaminA_RAE: form.vitaminA_RAE, retinol: form.retinol, caroteneAlpha: form.caroteneAlpha, caroteneBeta: form.caroteneBeta, cryptoxanthinBeta: form.cryptoxanthinBeta, luteinZeaxanthin: form.luteinZeaxanthin, lycopene: form.lycopene, vitaminB1_Thiamin: form.vitaminB1_Thiamin, vitaminB2_Riboflavin: form.vitaminB2_Riboflavin, vitaminB3_Niacin: form.vitaminB3_Niacin, vitaminB5_PantothenicAcid: form.vitaminB5_PantothenicAcid, vitaminB6: form.vitaminB6, folateDFE: form.folateDFE, folateFood: form.folateFood, folateTotal: form.folateTotal, folicAcid: form.folicAcid, vitaminB12: form.vitaminB12, vitaminC: form.vitaminC, vitaminD: form.vitaminD, vitaminE: form.vitaminE, vitaminK: form.vitaminK, choline: form.choline) }
    fileprivate func MineralsData(from form: MineralForm) -> MineralsData { .init(calcium: form.calcium, iron: form.iron, magnesium: form.magnesium, phosphorus: form.phosphorus, potassium: form.potassium, sodium: form.sodium, selenium: form.selenium, zinc: form.zinc, copper: form.copper, manganese: form.manganese, fluoride: form.fluoride) }
    fileprivate func OtherCompoundsData(from form: OtherForm) -> OtherCompoundsData {
            .init(
                alcoholEthyl: form.alcoholEthyl,
                caffeine: form.caffeine,
                theobromine: form.theobromine,
                cholesterol: form.cholesterol,
                energyKcal: form.energyKcal,
                water: form.water,
                weightG: form.weightG,
                ash: form.ash,
                betaine: form.betaine,
                alkalinityPH: form.alkalinityPH
            )
        }
    fileprivate func AminoAcidsData(from form: AminoAcidsForm) -> AminoAcidsData { .init(alanine: form.alanine, arginine: form.arginine, asparticAcid: form.asparticAcid, cystine: form.cystine, glutamicAcid: form.glutamicAcid, glycine: form.glycine, histidine: form.histidine, isoleucine: form.isoleucine, leucine: form.leucine, lysine: form.lysine, methionine: form.methionine, phenylalanine: form.phenylalanine, proline: form.proline, threonine: form.threonine, tryptophan: form.tryptophan, tyrosine: form.tyrosine, valine: form.valine, serine: form.serine, hydroxyproline: form.hydroxyproline) }
    fileprivate func CarbDetailsData(from form: CarbDetailsForm) -> CarbDetailsData { .init(starch: form.starch, sucrose: form.sucrose, glucose: form.glucose, fructose: form.fructose, lactose: form.lactose, maltose: form.maltose, galactose: form.galactose) }
    fileprivate func SterolsData(from form: SterolsForm) -> SterolsData { .init(phytosterols: form.phytosterols, betaSitosterol: form.betaSitosterol, campesterol: form.campesterol, stigmasterol: form.stigmasterol) }
    
    private struct FocusableNutrientRow: View {
        let row: NutrientRow
        var focusState: FocusState<FocusableField?>.Binding
        let focusID: FocusableField
        @ObservedObject private var effectManager = EffectManager.shared

        var body: some View {
            HStack {
                Text(row.label)
                Spacer()
                HStack(spacing: 4) {
                    ConfigurableTextField(
                        title: "0",
                        value: row.field,
                        type: .decimal,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        focused: focusState,
                        fieldIdentifier: focusID
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: row.field.wrappedValue) { _, newValue in
                        // --- НАЧАЛО НА ПРОМЯНАТА ---
                        // позволяваме празно (триене), но ограничаваме числата
                        guard !newValue.isEmpty,
                              let number = GlobalState.double(from: newValue) else { return }

                        if focusID == .alkalinityPH {
                            // ограничение 0–14
                            if number < 0 {
                                row.field.wrappedValue = "0"
                            } else if number > 14 {
                                row.field.wrappedValue = "14"
                            }
                        } else if number > 100000 {
                            // старото ограничение за всички други нутриенти
                            row.field.wrappedValue = "100000"
                        }
                        // --- КРАЙ НА ПРОМЯНАТА ---
                    }

                    Text(row.unit)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .id(focusID)
        }
    }

    
    // --- НАЧАЛО: Помощни функции за AIButton ---
    // --- AI Floating Button: Helpers ---
    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspect = size.height / size.width
        return aspect > 1.9 ? 75 : 95
    }
    private func aiTrailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }

    private func aiDragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($aiGestureDragOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.aiIsPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.aiIsDragging = true
                }
            }
            .onEnded { value in
                self.aiIsPressed = false
                if aiIsDragging {
                    var newOffset = self.aiButtonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height

                    // Ограничения по екрана
                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top
                    let maxY = -25 + safeArea.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))

                    self.aiButtonOffset = newOffset
                    self.saveAIButtonPosition()
                } else {
                    self.handleAITap()
                }
                self.aiIsDragging = false
            }
    }

    private func handleAITap() {
        
        guard ensureAIAvailableOrShowMessage() else { return }

        
           guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
               alertMsg = "Please enter a name for the food first."
               showAlert = true
               return
           }
           
           focusedField = nil
           hasUserMadeEdits = false // Mark as edited to prevent overwrites from other AI processes

           if #available(iOS 26.0, *) {
               triggerAIGenerationToast()

               if let newJob = aiManager.startFoodDetailGeneration(
                   for: self.profile,
                   foodName: self.name,
                   jobType: .foodItemDetail
               ) {
                   self.runningGenerationJobID = newJob.id
               } else {
                   alertMsg = "Could not start AI generation job."
                   showAlert = true
                   toastTimer?.invalidate()
                   toastTimer = nil
                   withAnimation { showAIGenerationToast = false }
               }
           } else {
               alertMsg = "AI data generation requires iOS 26 or newer."
               showAlert = true
           }
       }

    private func triggerAIGenerationToast() {
           toastTimer?.invalidate()
           toastProgress = 0.0
           withAnimation {
               showAIGenerationToast = true
           }

           let totalDuration = 5.0 // Give it a longer timeout
           let updateInterval = 0.1
           let progressIncrement = updateInterval / totalDuration

           toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
               DispatchQueue.main.async {
                   self.toastProgress += progressIncrement
                   if self.toastProgress >= 1.0 {
                       timer.invalidate()
                       self.toastTimer = nil
                       withAnimation {
                           self.showAIGenerationToast = false
                       }
                   }
               }
           }
       }
    
    private func saveAIButtonPosition() {
        let d = UserDefaults.standard
        d.set(aiButtonOffset.width,  forKey: "\(aiButtonPositionKey)_width")
        d.set(aiButtonOffset.height, forKey: "\(aiButtonPositionKey)_height")
    }

    private func loadAIButtonPosition() {
        let d = UserDefaults.standard
        let w = d.double(forKey: "\(aiButtonPositionKey)_width")
        let h = d.double(forKey: "\(aiButtonPositionKey)_height")
        self.aiButtonOffset = CGSize(width: w, height: h)
    }

    @ViewBuilder
    private func AIButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(
            width: aiButtonOffset.width + aiGestureDragOffset.width,
            height: aiButtonOffset.height + aiGestureDragOffset.height
        )
        let scale = aiIsDragging ? 1.15 : (aiIsPressed ? 0.9 : 1.0)

        Image(systemName: "sparkles")
            .font(.title2)            .foregroundColor(effectManager.currentGlobalAccentColor)
            .frame(width: 60, height: 60)
            .glassCardStyle(cornerRadius: 32)
            .scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aiIsDragging)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aiIsPressed)
            .padding(.trailing, aiTrailingPadding(for: geometry))
            .padding(.bottom, aiBottomPadding(for: geometry))
            .contentShape(Rectangle())
            .offset(currentOffset)
            .opacity(isAIButtonVisible ? 1 : 0)
            .disabled(!isAIButtonVisible)
            .gesture(aiDragGesture(geometry: geometry))
            .transition(.scale.combined(with: .opacity))
    }
}

extension FoodItemEditorView.OpenMenu {
    var title: String {
        switch self {
        case .category: return "Category"
        case .diet: return "Diets"
        case .allergen: return "Allergens"
        case .none: return ""
        }
    }
}


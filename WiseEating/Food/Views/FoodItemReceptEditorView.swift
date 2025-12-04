import SwiftUI
import SwiftData
import PhotosUI

@MainActor
struct FoodItemReceptEditorView: View {
    @State private var selectedNutrientID: String? = nil
    @State private var aiIsPressed: Bool = false
    @ObservedObject private var aiManager = AIManager.shared
    @State private var hasUserMadeEdits: Bool = false
    @State private var runningGenerationJobID: UUID? = nil
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
       
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    private let aiButtonPositionKey = "floatingRecipeAIButtonPosition"
    
    @FocusState.Binding var isSearchFieldFocused: Bool

    // MARK: - Managers and Environment
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var ctx
    @Environment(\.colorScheme)  private var colorScheme
    let onDismiss: (FoodItem?) -> Void
    @State private var scrollToIngredientID: FoodItem.ID? = nil

    // MARK: - Data Queries
    @Query(sort: \Vitamin.name)  private var allVitamins:  [Vitamin]
    @Query(sort: \Mineral.name)  private var allMinerals:  [Mineral]
    @Query(sort: \Diet.name) private var allDiets: [Diet]

    // MARK: - Input Properties
    let food: FoodItem?
    let profile: Profile?
    private let dubFood: FoodItemCopy?
    @State private var origRecipe: FoodItem? = nil

    // MARK: - State Variables
    @State private var name: String
    @State private var itemDescription: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var prepTimeTxt: String
    @State private var minAgeMonthsTxt: String

    @State private var selectedIng: [FoodItem: Double] = [:] // FoodItem → grams
    @State private var ingredientTextValues: [FoodItem.ID: String] = [:]

    enum FocusableField: Hashable {
        case name, description, prepTime, minAge
        case ingredientGrams(FoodItem.ID)
    }
    @FocusState private var focusedField: FocusableField?
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var ingredientUnit: String { isImperial ? "oz" : "g" }
    private var servingUnit: String { isImperial ? "oz" : "g" }
    
    // Tags
    @State private var selectedCategories: Set<FoodCategory.ID>
    @State private var selectedDiets: Set<Diet.ID>
    @State private var selectedAllergens: Set<Allergen.ID>
    
    // Gallery
    @State private var galleryData: [Data] = []
    @State private var newGalleryItems: [PhotosPickerItem] = []
    @State private var showReplacePicker  = false
    @State private var replacementItem: PhotosPickerItem?
    @State private var replaceAtIndex: Int?
    @State private var tappedIndex: Int?  = nil
    @State private var showPopover = false
    
    // Collapsible sections state
    @State private var showMacros       = true
    @State private var showLipids       = false
    @State private var showOther        = false
    @State private var showMoreVitamins = false
    @State private var showMoreMinerals = false
    @State private var showAminoAcids = false
    @State private var showCarbDetails = false
    @State private var showSterols = false
    
    @State private var showAlert = false
    @State private var alertMsg  = ""
    
    // Global Search Integration
    @Binding var globalSearchText: String

    // Nutrient Forms (Read-Only)
    @State private var macros: MacroForm
    @State private var lipids: LipidForm
    @State private var vitamins: VitaminForm
    @State private var minerals: MineralForm
    @State private var others: OtherForm
    @State private var aminoAcids: AminoAcidsForm
    @State private var carbDetails: CarbDetailsForm
    @State private var sterols: SterolsForm
    
    @State private var calculatedMinAge: Int = 0
    
    private let isReadOnly = true

    @State private var isSaving = false
    @State private var isAIInit = false

    // MARK: - Initializer
    init(
        dubFood: FoodItemCopy? = nil,
        food: FoodItem? = nil,
        profile: Profile? = nil,
        globalSearchText: Binding<String>,
        onDismiss: @escaping (FoodItem?) -> Void,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        isAIInit: Bool? = false
    ) {
        self.isAIInit = isAIInit!
        self._isSearchFieldFocused = isSearchFieldFocused
        self.dubFood  = dubFood
        self.food     = food
        self.profile  = profile
        self._globalSearchText = globalSearchText
        self.onDismiss = onDismiss
        
        var initialName = ""
        var initialDescription = ""
        var initialPhotoData: Data? = nil
        var initialPrepTimeTxt = ""
        var initialMinAgeMonthsTxt = ""
        var initialSelectedIng: [FoodItem: Double] = [:]
        var initialMacros = MacroForm()
        var initialLipids = LipidForm()
        var initialVitamins = VitaminForm()
        var initialMinerals = MineralForm()
        var initialOthers = OtherForm()
        var initialAminoAcids = AminoAcidsForm()
        var initialCarbDetails = CarbDetailsForm()
        var initialSterols = SterolsForm()
        var initialSelectedCategories = Set<FoodCategory.ID>()
        var initialSelectedDiets = Set<Diet.ID>()
        var initialSelectedAllergens = Set<Allergen.ID>()
        var initialGalleryData: [Data] = []
        
        if let f = food {
            initialName = f.name
            initialPhotoData = f.photo
            initialDescription = f.itemDescription ?? ""
            initialPrepTimeTxt = f.prepTimeMinutes.map { String($0) } ?? ""
            initialMinAgeMonthsTxt = f.minAgeMonths > 0 ? String(f.minAgeMonths) : ""
            
            if let links = f.ingredients {
                let pairs = links.compactMap { link -> (FoodItem, Double)? in
                    guard let food = link.food else { return nil }
                    return (food, link.grams)
                }
                initialSelectedIng = Dictionary(grouping: pairs, by: { $0.0 })
                    .mapValues { $0.reduce(0.0) { $0 + $1.1 } }
            }
            
            let totals = FoodItem.aggregatedNutrition(for: f)
            initialMacros = MacroForm(from: totals.macros)
            initialLipids = LipidForm(from: totals.lipids)
            initialVitamins = VitaminForm(from: totals.vitamins)
            initialMinerals = MineralForm(from: totals.minerals)
            initialOthers = OtherForm(from: totals.other)
            initialAminoAcids = AminoAcidsForm(from: totals.aminoAcids)
            initialCarbDetails = CarbDetailsForm(from: totals.carbDetails)
            initialSterols = SterolsForm(from: totals.sterols)

            let tags = Self.aggregatedTags(for: f)
            initialSelectedCategories = tags.categories
            initialSelectedDiets = tags.diets
            initialSelectedAllergens = tags.allergens
            
            if let photos = f.gallery {
                initialGalleryData = photos.map(\.data)
            }
        }
        
        if let d = dubFood {
            initialName = isAIInit! ? d.name : "Copy of \(d.name)"
        }
        
        _name = State(initialValue: initialName)
        _itemDescription = State(initialValue: initialDescription)
        _photoData = State(initialValue: initialPhotoData)
        _prepTimeTxt = State(initialValue: initialPrepTimeTxt)
        _minAgeMonthsTxt = State(initialValue: initialMinAgeMonthsTxt)
        _selectedIng = State(initialValue: initialSelectedIng)
        _macros = State(initialValue: initialMacros)
        _lipids = State(initialValue: initialLipids)
        _vitamins = State(initialValue: initialVitamins)
        _minerals = State(initialValue: initialMinerals)
        _others = State(initialValue: initialOthers)
        _aminoAcids = State(initialValue: initialAminoAcids)
        _carbDetails = State(initialValue: initialCarbDetails)
        _sterols = State(initialValue: initialSterols)
        _selectedCategories = State(initialValue: initialSelectedCategories)
        _selectedDiets = State(initialValue: initialSelectedDiets)
        _selectedAllergens = State(initialValue: initialSelectedAllergens)
        _galleryData = State(initialValue: initialGalleryData)
    }

    // MARK: - Body & Toolbar
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
               .onAppear {
                   ingredientTextValues = Dictionary(uniqueKeysWithValues: selectedIng.map { (item, grams) in
                       let displayValue = isImperial ? UnitConversion.gToOz(grams) : grams
                       return (item.id, GlobalState.formatDecimalString(String(displayValue)))
                   })
                   recalculateAndValidateMinAge()
               }
               .onChange(of: selectedIng) { _, newIngredients in
                    recalcTotals()
                    recalcTags()
                    recalculateAndValidateMinAge()
                }
               .task(id: dubFood?.id) {
                   await loadFromDubFood()
               }
               .disabled(isSaving)
               .blur(radius: isSaving ? 1.5 : 0)
               
               // +++ НАЧАЛО НА ПРОМЯНАТА: Замяна с FoodSearchPanelView +++
               if isSearchFieldFocused {
                   let focusBinding = Binding<Bool>(
                       get: { isSearchFieldFocused },
                       set: { isSearchFieldFocused = $0 }
                   )
                   
                   // Изчисляваме ID-тата, които да скрием (тези, които вече са добавени)
                   let excludedIDs = Set(selectedIng.keys.map { $0.id })
                   
                   FoodSearchPanelView(
                       globalSearchText: $globalSearchText,
                       isSearchFieldFocused: focusBinding,
                       profile: profile,
                       searchMode: .recipes, // nil позволява търсене и на храни, и на други рецепти
                       showFavoritesFilter: true,
                       showRecipesFilter: false,
                       showMenusFilter: false, // За рецепти обикновено не добавяме менюта като съставки
                       headerRightText: nil,
                       excludedFoodIDs: excludedIDs,
                       onSelectFood: { foodItem in
                           selectIngredient(foodItem)
                       },
                       onDismiss: {
                           dismissKeyboardAndSearch()
                       }
                   )
                   .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                   .zIndex(1)
               }
               // +++ КРАЙ НА ПРОМЯНАТА +++

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
                       if !isSearchFieldFocused &&
                            !isSaving &&
                            !showPopover &&
                            !showReplacePicker &&
                            GlobalState.aiAvailability != .deviceNotEligible {
                           AIButton(geometry: geometry)
                       }
                   }
                   .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
               }
           }
           .onReceive(NotificationCenter.default.publisher(for: .aiRecipeJobCompleted)) { notification in
               guard !hasUserMadeEdits,
                     let userInfo = notification.userInfo,
                     let completedJobID = userInfo["jobID"] as? UUID,
                     completedJobID == self.runningGenerationJobID else {
                   return
               }

               print("▶️ FoodItemReceptEditorView: Received .aiRecipeJobCompleted for job \(completedJobID). Populating data.")
               
               Task {
                   if #available(iOS 26.0, *) {
                       await populateFromCompletedJob(jobID: completedJobID)
                   }
               }
           }
           .onChange(of: name) { _, _ in hasUserMadeEdits = true }
           .onChange(of: itemDescription) { _, _ in hasUserMadeEdits = true }
           .onChange(of: selectedIng) { _, _ in hasUserMadeEdits = true }
           .onAppear { loadAIButtonPosition() }
       }

    @ViewBuilder
    private var customToolbar: some View {
        let title = food?.isMenu == true ? (food == nil ? "Add Menu" : "Edit Menu") : (food == nil ? "Add Recipe" : "Edit Recipe")
        HStack {
            HStack { Button("Cancel") { onDismiss(nil) } }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            Spacer()

            Text(title)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            Spacer()

            let isSaveDisabled = name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving
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
    
    // MARK: - Form Body
    private var mainForm: some View {
           ScrollViewReader { proxy in
               ScrollView(showsIndicators: false) {
                   VStack(spacing: 0) {
                       basicSection
                       gallerySection
                       if !selectedIng.isEmpty {
                           ingredientsSection
                       }
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
               .onChange(of: focusedField) { oldValue, newValue in
                   if let oldID = oldValue, newValue != oldID {
                       switch oldID {
                       case .ingredientGrams(let foodItemID):
                           formatIngredientText(for: foodItemID)
                       case .minAge:
                           validateMinAgeOnBlur()
                       default:
                           break
                       }
                   }

                   guard let focus = newValue else { return }

                   let idToScroll: AnyHashable
                   switch focus {
                   case .name, .description, .prepTime, .minAge:
                       idToScroll = focus
                   case .ingredientGrams(let foodItemID):
                       idToScroll = foodItemID
                   }

                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                       withAnimation(.easeInOut(duration: 0.3)) {
                           proxy.scrollTo(idToScroll, anchor: .top)
                       }
                   }
               }
               .onChange(of: scrollToIngredientID) { _, newID in
                   guard let id = newID else { return }
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                       withAnimation(.easeInOut) {
                           proxy.scrollTo(id, anchor: .top)
                       }
                       scrollToIngredientID = nil
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
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(.bottom, -4)
            
            VStack(spacing: 12) {
                let prompt = food?.isMenu == true ? "Menu Name" : "Recipe Name"
                StyledLabeledPicker(label: "Name", isRequired: true) {
                    TextField(
                        prompt,
                        text: $name,
                        prompt: Text(prompt)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    )
                    .font(.system(size: 16))
                    .focused($focusedField, equals: .name)
                    .disableAutocorrection(true)
                }
                .id(FocusableField.name)
                
                HStack(spacing: 16) {
                    photoPicker
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Prep time
                        StyledLabeledPicker(label: "Prep time (min)") {
                            ConfigurableTextField(
                                title: "e.g. 45",
                                value: $prepTimeTxt,
                                type: .integer,
                                placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                                textAlignment: .leading,
                                focused: $focusedField,
                                fieldIdentifier: .prepTime
                            )
                            .font(.system(size: 16))
                        }
                        .id(FocusableField.prepTime)
                        
                        // Description
                        StyledLabeledPicker(label: "Description", height: 120) {
                            descriptionEditor
                                .focused($focusedField, equals: .description)
                        }
                        .id(FocusableField.description)
                    }
                }
                
                VStack(spacing: 12) {
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
                    
                    if let sourceText = minAgeSourceDescription {
                        Text(sourceText)
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Category
                    tagPicker(
                        label: "Category",
                        selection: $selectedCategories,
                        items: FoodCategory.allCases.sorted { $0.rawValue < $1.rawValue },
                        itemLabel: { $0.rawValue }
                    )
                    
                    // --- DIETS + DETAILS ---
                    VStack(alignment: .leading, spacing: 4) {
                        tagPicker(
                            label: "Diets",
                            selection: $selectedDiets,
                            items: allDiets,
                            itemLabel: { $0.name }
                        )
                        
                        if showsDietMismatchWarning {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("⚠️ This recipe does not match any of the user's diets.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                
                                if !selectedDietNames.isEmpty {
                                    Text("Recipe diets: \(selectedDietNames)")
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
                    
                    // --- ALLERGENS + DETAILS ---
                    VStack(alignment: .leading, spacing: 4) {
                        tagPicker(
                            label: "Allergens",
                            selection: $selectedAllergens,
                            items: Allergen.allCases,
                            itemLabel: { $0.rawValue }
                        )
                        
                        if !matchingProfileAllergens.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("⚠️ This recipe contains allergens the user is sensitive to.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                
                                if !foodAllergenNames.isEmpty {
                                    Text("Recipe allergens: \(foodAllergenNames)")
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
        return Allergen.allCases.filter {
            selectedAllergens.contains($0.id) && profileAllergenIDs.contains($0.id)
        }
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
        // Need both: user has diets AND recipe has diets
        guard !profileDietIDs.isEmpty else { return false }
        guard !selectedDiets.isEmpty else { return false }
        // Show warning when there is no overlap
        return selectedDiets.isDisjoint(with: profileDietIDs)
    }

    private var minAgeSourceDescription: String? {
        guard calculatedMinAge > 0 else { return nil }
        let sourceFoods = selectedIng.keys.filter { $0.minAgeMonths == calculatedMinAge }.sorted { $0.name < $1.name }
        guard !sourceFoods.isEmpty else { return nil }
        let names = sourceFoods.map(\.name)
        if names.count == 1 {
            return "Minimum age is determined by: \(names[0]) (\(calculatedMinAge) months)."
        } else if names.count == 2 {
            return "Minimum age is determined by: \(names[0]) and \(names[1]) (\(calculatedMinAge) months)."
        } else {
            let firstTwo = names.prefix(2).joined(separator: ", ")
            return "Minimum age is determined by: \(firstTwo) and \(names.count - 2) more (\(calculatedMinAge) months)."
        }
    }

    
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gallery")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            VStack { galleryGrid }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .photosPicker(isPresented: $showReplacePicker, selection: $replacementItem, matching: .images)
                .onChange(of: replacementItem, handleReplacementItemChange)
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var ingredientsSection: some View {
              VStack(alignment: .leading, spacing: 8) {
                  let title = food?.isMenu == true ? "Foods in Menu" : "Ingredients"
                  Text(title)
                      .font(.headline)
                      .foregroundStyle(effectManager.currentGlobalAccentColor)
                  
                  VStack(spacing: 12) {
                      ForEach(Array(selectedIng.keys.sorted(by: { $0.name < $1.name })), id: \.self) { item in
                          let gramsBinding = Binding<Double>(
                              get: { selectedIng[item] ?? 0.0 },
                              set: { selectedIng[item] = $0 }
                          )
                          
                          IngredientRowView(
                              grams: gramsBinding,
                              item: item,
                              focusedField: $focusedField,
                              focusCase: .ingredientGrams(item.id),
                              onDelete: {
                                  selectedIng.removeValue(forKey: item)
                              }
                          )
                          .id(item.id)
                      }
                  }
                  .padding()
                  .glassCardStyle(cornerRadius: 20)
              }
              .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          }
    
    private var macroSection: some View {
       VStack(alignment: .leading, spacing: 8) {
           collapsibleHeader("Macronutrients", isExpanded: $showMacros)
           if showMacros {
               VStack(spacing: 12) { macroGrid }
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
    
    private var vitaminSection: some View {
        let allRows = vitaminRows()
        let priorityNames = Set(profile?.priorityVitamins.map(label(for:)) ?? [])
        let (prio, other) = splitRows(allRows, priorityNames: priorityNames)
        
        return VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader("Vitamins", isExpanded: $showMoreVitamins, hasOtherItems: !other.isEmpty)
            if !prio.isEmpty || (showMoreVitamins && !other.isEmpty) {
                VStack(spacing: 12) {
                    nutrientGrid(prio)
                    if showMoreVitamins { nutrientGrid(other) }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    private var mineralSection: some View {
        let allRows = mineralRows()
        let priorityNames = Set(profile?.priorityMinerals.map(label(for:)) ?? [])
        let (prio, other) = splitRows(allRows, priorityNames: priorityNames)
        
        return VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader("Minerals", isExpanded: $showMoreMinerals, hasOtherItems: !other.isEmpty)
            if !prio.isEmpty || (showMoreMinerals && !other.isEmpty) {
                VStack(spacing: 12) {
                    nutrientGrid(prio)
                    if showMoreMinerals { nutrientGrid(other) }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    private var aminoAcidsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader("Amino Acids", isExpanded: $showAminoAcids)
            if showAminoAcids {
                VStack(spacing: 12) {
                    nutrientGrid(aminoAcidRows())
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var carbDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader("Carbohydrate Details", isExpanded: $showCarbDetails)
            if showCarbDetails {
                VStack(spacing: 12) {
                    nutrientGrid(carbDetailRows())
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    private var sterolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader("Sterols", isExpanded: $showSterols)
            if showSterols {
                VStack(spacing: 12) {
                    nutrientGrid(sterolRows())
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    // MARK: - Subviews & Helpers
    private var photoPicker: some View {
        let imageData = photoData
        let color = effectManager.currentGlobalAccentColor.opacity(0.6)

        return PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Group {
                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
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
        .onChange(of: selectedPhoto, handleNewPhotoSelection)
        .padding(.leading, -4)
    }

    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            if itemDescription.isEmpty {
                Text("Recipe instructions, notes, etc.")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .font(.system(size: 16))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 8)
            }
            TextEditor(text: $itemDescription)
                .font(.system(size: 16))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
    }
        
    private var galleryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(Array(galleryData.enumerated()), id: \.offset) { index, data in
                if let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: 80, height: 80).clipped().cornerRadius(8)
                        .onLongPressGesture { tappedIndex = index; showPopover = true }
                        .popover(isPresented: popoverBinding(for: index), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            galleryPopoverContent(for: index, data: data)
                        }
                }
            }
            let color = effectManager.currentGlobalAccentColor
            PhotosPicker(selection: $newGalleryItems, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).stroke(style: .init(lineWidth: 1, dash: [4])).frame(width: 80, height: 80)
                    Image(systemName: "plus").font(.title2.weight(.semibold))
                }.foregroundColor(color)
            }
            .onChange(of: newGalleryItems, handleNewGalleryItems)
        }
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
                    Text(row.field.wrappedValue.isEmpty ? "—" : Double(row.field.wrappedValue)?.formatted(.number.precision(.fractionLength(2))) ?? "—")
                        .frame(width: 80, alignment: .trailing)
                    Text(row.unit).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
    }
    
    @ViewBuilder
    private func tagPicker<I: Identifiable & Hashable>(
        label: String,
        selection: Binding<Set<I.ID>>,
        items: [I],
        itemLabel: @escaping (I) -> String
    ) -> some View {
        StyledLabeledPicker(label: label, isFixedHeight: false) {
            MultiSelectButton(
                selection: selection,
                items: items,
                label: itemLabel,
                prompt: "",
                isExpanded: false,
                disabled: true
            )
            .contentShape(Rectangle())
            .font(.system(size: 16))
        }
    }
    
    private func nextFoodId() -> Int {
        var desc = FetchDescriptor<FoodItem>()
        desc.sortBy = [SortDescriptor(\FoodItem.id, order: .reverse)]
        desc.fetchLimit = 1

        let maxId = ((try? ctx.fetch(desc))?.first?.id) ?? 0
        return maxId + 1
    }
    
    // MARK: - Logic & Actions
    private func save() {
        Task { @MainActor in
            isSaving = true
            await Task.yield()
            defer { isSaving = false }
            let recipe: FoodItem
            if isAIInit{
                 recipe = food ?? origRecipe ?? {
                    let r = FoodItem(id: nextFoodId(), name: name, isRecipe: true, isUserAdded: true)
                    ctx.insert(r)
                    return r
                }()
            }else{
                 recipe = food ?? {
                    let r = FoodItem(id: nextFoodId(), name: name, isRecipe: true, isUserAdded: true)
                    ctx.insert(r)
                    return r
                }()
            }
            
            recipe.name  = name
            recipe.photo = photoData
            recipe.itemDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            recipe.prepTimeMinutes = Int(prepTimeTxt)
            recipe.minAgeMonths    = Int(minAgeMonthsTxt) ?? 0

            recipe.category  = idsToEnums(selectedCategories, of: FoodCategory.self)
            
            let chosenDiets = allDiets.filter { selectedDiets.contains($0.id) }
            recipe.diets = chosenDiets.isEmpty ? nil : chosenDiets
            
            recipe.allergens = idsToEnums(selectedAllergens, of: Allergen.self)
            recipe.isRecipe     = true
            recipe.isUserAdded  = true
            
            if recipe.gallery == nil { recipe.gallery = [] }
            recipe.gallery?.removeAll { photo in !galleryData.contains(photo.data) }
            for data in galleryData {
                if !(recipe.gallery?.contains(where: { $0.data == data }) ?? false) {
                    recipe.gallery?.append(FoodPhoto(data: data))
                }
            }
            
            if let existingLinks = recipe.ingredients {
                for link in existingLinks { ctx.delete(link) }
            }
            recipe.ingredients = []

            for (foodItem, grams) in selectedIng where grams > 0 {
                let newLink = IngredientLink(food: foodItem, grams: grams, owner: recipe)
                recipe.ingredients?.append(newLink)
            }

            do {
                try ctx.save()
                SearchIndexStore.shared.updateItem(recipe, context: ctx)
                onDismiss(recipe)
            } catch {
                alertMsg = error.localizedDescription
                showAlert = true
            }
        }
    }
    private func loadFromDubFood() async {
        guard let copy = dubFood else { return }
        let original = copy.toOriginal(in: ctx)
        await MainActor.run {
            origRecipe    = original
            let initialName = isAIInit ? copy.name : "Copy of \(copy.name)"
            name          = initialName
            photoData     = copy.photo
            itemDescription = copy.itemDescription ?? ""
            prepTimeTxt   = copy.prepTimeMinutes.map { String($0) } ?? ""
            minAgeMonthsTxt = original.minAgeMonths > 0 ? String(original.minAgeMonths) : ""
            
            if let links = original.ingredients {
                let pairs = links.compactMap { link -> (FoodItem, Double)? in
                    guard let food = link.food else { return nil }
                    return (food, link.grams)
                }
                selectedIng = Dictionary(grouping: pairs, by: { $0.0 })
                    .mapValues { $0.reduce(0.0) { $0 + $1.1 } }
            }
            
            recalcTotals()
            recalcTags()
            galleryData = copy.gallery?.map(\.data) ?? []
        }
    }

    private func galleryPopoverContent(for index: Int, data: Data) -> some View {
        HStack(spacing: 0) {
            Button("Set as main") { photoData = data; showPopover = false }.frame(maxWidth: .infinity)
            Divider()
            Button("Change") { replaceAtIndex = index; showPopover = false; showReplacePicker = true }.frame(maxWidth: .infinity)
            Divider()
            Button(role: .destructive) { galleryData.remove(at: index); showPopover = false } label: { Text("Remove") }.frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.none)
    }

    private func handleNewPhotoSelection(_: PhotosPickerItem?, newItem: PhotosPickerItem?) {
        Task {
            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                await MainActor.run { photoData = data }
            }
        }
    }
    
    private func handleNewGalleryItems(_: [PhotosPickerItem], items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let d = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { galleryData.append(d) }
                }
            }
            await MainActor.run { newGalleryItems.removeAll() }
        }
    }
    
    private func handleReplacementItemChange(_: PhotosPickerItem?, item: PhotosPickerItem?) {
        guard let idx = replaceAtIndex, let item else { return }
        Task {
            if let d = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { galleryData[idx] = d }
            }
            await MainActor.run {
                replacementItem = nil
                replaceAtIndex  = nil
            }
        }
    }
    
    private func popoverBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { showPopover && tappedIndex == index },
            set: { showPopover = $0 }
        )
    }

    private func selectIngredient(_ item: FoodItem) {
          let defaultGrams = isImperial ? UnitConversion.ozToG(4.0) : 100.0
          selectedIng[item, default: 0] += defaultGrams
          globalSearchText = ""
          dismissKeyboardAndSearch()
          scrollToIngredientID = item.id
      }
    
    private func idsToEnums<E: CaseIterable & Identifiable>(_ ids: Set<E.ID>, of _: E.Type) -> [E]? where E.ID == String {
        let all = E.allCases as! [E]
        let filtered = all.filter { ids.contains($0.id) }
        return filtered.isEmpty ? nil : filtered
    }
    
    private enum NutrientItem: Identifiable, Hashable {
        case vitamin(Vitamin)
        case mineral(Mineral)
        var id: String {
            switch self {
            case .vitamin(let v): "vit_\(v.id)"
            case .mineral(let m): "min_\(m.id)"
            }
        }
        var name: String {
            switch self {
            case .vitamin(let v): v.name
            case .mineral(let m): m.name
            }
        }
    }
    
    private var allNutrients: [NutrientItem] {
        allVitamins.map(NutrientItem.vitamin) + allMinerals.map(NutrientItem.mineral)
    }
    
    private var selectedNutrientName: String {
        guard let id = selectedNutrientID, let nutrient = allNutrients.first(where: { $0.id == id }) else { return "None" }
        return nutrient.name
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func formatIngredientText(for itemId: FoodItem.ID) {
        guard let item = selectedIng.keys.first(where: { $0.id == itemId }),
              let grams = selectedIng[item] else { return }
        let displayValue = isImperial ? UnitConversion.gToOz(grams) : grams
        ingredientTextValues[itemId] = GlobalState.formatDecimalString(String(displayValue))
    }
    
    // MARK: - Calculation & Aggregation
    
    private func recalculateAndValidateMinAge() {
        let requiredMinAge = selectedIng.keys.map { $0.minAgeMonths }.max() ?? 0
        self.calculatedMinAge = requiredMinAge

        let currentUserAge = Int(minAgeMonthsTxt) ?? 0

        if currentUserAge < requiredMinAge || (minAgeMonthsTxt.isEmpty && requiredMinAge > 0) {
            minAgeMonthsTxt = String(requiredMinAge)
        }
    }
    
    private func validateMinAgeOnBlur() {
        let currentUserAge = Int(minAgeMonthsTxt) ?? 0
        if currentUserAge < calculatedMinAge {
            minAgeMonthsTxt = String(calculatedMinAge)
        }
    }
    
    @inline(__always) private func nv(_ n: Nutrient?) -> Double { n?.value ?? 0 }
    @inline(__always) private func n(_ x: Double, _ unit: String) -> Nutrient? { x > 0 ? Nutrient(value: x, unit: unit) : nil }

    private func recalcTotals() {
        var totalGrams: Double = 0

        // Macros
        var sumCarbs = 0.0, sumProtein = 0.0, sumFat = 0.0, sumFiber = 0.0, sumSugars = 0.0
        // Other
        var sumEnergy = 0.0, sumAlcohol = 0.0, sumCaffeine = 0.0, sumTheobromine = 0.0
        var sumCholesterol = 0.0, sumWater = 0.0, sumAsh = 0.0, sumBetaine = 0.0
        // Lipids totals
        var sumSat = 0.0, sumMono = 0.0, sumPoly = 0.0, sumTrans = 0.0, sumTransMono = 0.0, sumTransPoly = 0.0
        // SFA
        var sfa4 = 0.0, sfa6 = 0.0, sfa8 = 0.0, sfa10 = 0.0, sfa12 = 0.0, sfa13 = 0.0, sfa14 = 0.0, sfa15 = 0.0
        var sfa16 = 0.0, sfa17 = 0.0, sfa18 = 0.0, sfa20 = 0.0, sfa22 = 0.0, sfa24 = 0.0
        // MUFA
        var mufa14_1 = 0.0, mufa15_1 = 0.0, mufa16_1 = 0.0, mufa17_1 = 0.0, mufa18_1 = 0.0, mufa20_1 = 0.0, mufa22_1 = 0.0, mufa24_1 = 0.0
        // TFA
        var tfa16_1_t = 0.0, tfa18_1_t = 0.0, tfa22_1_t = 0.0, tfa18_2_t = 0.0
        // PUFA
        var pufa18_2 = 0.0, pufa18_3 = 0.0, pufa18_4 = 0.0, pufa20_2 = 0.0, pufa20_3 = 0.0, pufa20_4 = 0.0
        var pufa20_5 = 0.0, pufa21_5 = 0.0, pufa22_4 = 0.0, pufa22_5 = 0.0, pufa22_6 = 0.0, pufa2_4 = 0.0

        // Vitamins
        var vA = 0.0, retinol = 0.0, carotAlpha = 0.0, carotBeta = 0.0, cryptoxBeta = 0.0, lutein = 0.0, lycopene = 0.0
        var b1 = 0.0, b2 = 0.0, b3 = 0.0, b5 = 0.0, b6 = 0.0
        var folateDFE = 0.0, folateFood = 0.0, folateTotal = 0.0, folicAcid = 0.0, b12 = 0.0, vC = 0.0, vD = 0.0, vE = 0.0, vK = 0.0, choline = 0.0
        // Minerals
        var calcium = 0.0, phosphorus = 0.0, magnesium = 0.0, potassium = 0.0, sodium = 0.0
        var iron = 0.0, zinc = 0.0, copper = 0.0, manganese = 0.0, selenium = 0.0, fluoride = 0.0
        // Amino acids
        var alanine = 0.0, arginine = 0.0, aspartic = 0.0, cystine = 0.0, glutamic = 0.0, glycine = 0.0
        var histidine = 0.0, isoleucine = 0.0, leucine = 0.0, lysine = 0.0, methionine = 0.0
        var phenylalanine = 0.0, proline = 0.0, threonine = 0.0, tryptophan = 0.0, tyrosine = 0.0, valine = 0.0, serine = 0.0, hydroxyproline = 0.0
        // Carb details
        var starch = 0.0, sucrose = 0.0, glucose = 0.0, fructose = 0.0, lactose = 0.0, maltose = 0.0, galactose = 0.0
        // Sterols
        var phytosterols = 0.0, betaSitosterol = 0.0, campesterol = 0.0, stigmasterol = 0.0

        // --- НОВО: агрегиране на pH логаритмично ---
        var hPlusSum = 0.0       // Σ [H+] * маса
        var hPlusWeight = 0.0    // Σ маса (g) за които имаме pH

        for (food, grams) in selectedIng {
            guard grams > 0 else { continue }
            let base = food.other?.weightG?.value ?? 100.0
            guard base > 0 else { continue }
            let f = grams / base
            totalGrams += grams

            // Macros
            sumCarbs     += f * nv(food.macronutrients?.carbohydrates)
            sumProtein   += f * nv(food.macronutrients?.protein)
            sumFat       += f * nv(food.macronutrients?.fat)
            sumFiber     += f * nv(food.macronutrients?.fiber)
            sumSugars    += f * nv(food.macronutrients?.totalSugars)

            // Other
            sumEnergy      += f * nv(food.other?.energyKcal)
            sumAlcohol     += f * nv(food.other?.alcoholEthyl)
            sumCaffeine    += f * nv(food.other?.caffeine)
            sumTheobromine += f * nv(food.other?.theobromine)
            sumCholesterol += f * nv(food.other?.cholesterol)
            let waterForThisFood = f * nv(food.other?.water)
            sumWater       += waterForThisFood
            sumAsh         += f * nv(food.other?.ash)
            sumBetaine     += f * nv(food.other?.betaine)

            // --- НОВО: pH от отделната храна ---
            if let phValue = food.other?.alkalinityPH?.value, phValue > 0 {
                let h = pow(10.0, -phValue)  // [H+] за тази храна
                // Ползваме грамовете от съставката като тегло (както в примера 100 g и 200 g)
                let weight = grams
                hPlusSum += h * weight
                hPlusWeight += weight
            }


            // Lipids totals
            sumSat      += f * nv(food.lipids?.totalSaturated)
            sumMono     += f * nv(food.lipids?.totalMonounsaturated)
            sumPoly     += f * nv(food.lipids?.totalPolyunsaturated)
            sumTrans    += f * nv(food.lipids?.totalTrans)
            sumTransMono += f * nv(food.lipids?.totalTransMonoenoic)
            sumTransPoly += f * nv(food.lipids?.totalTransPolyenoic)

            // SFA
            sfa4  += f * nv(food.lipids?.sfa4_0);   sfa6  += f * nv(food.lipids?.sfa6_0)
            sfa8  += f * nv(food.lipids?.sfa8_0);   sfa10 += f * nv(food.lipids?.sfa10_0)
            sfa12 += f * nv(food.lipids?.sfa12_0);  sfa13 += f * nv(food.lipids?.sfa13_0)
            sfa14 += f * nv(food.lipids?.sfa14_0);  sfa15 += f * nv(food.lipids?.sfa15_0)
            sfa16 += f * nv(food.lipids?.sfa16_0);  sfa17 += f * nv(food.lipids?.sfa17_0)
            sfa18 += f * nv(food.lipids?.sfa18_0);  sfa20 += f * nv(food.lipids?.sfa20_0)
            sfa22 += f * nv(food.lipids?.sfa22_0);  sfa24 += f * nv(food.lipids?.sfa24_0)

            // MUFA
            mufa14_1 += f * nv(food.lipids?.mufa14_1); mufa15_1 += f * nv(food.lipids?.mufa15_1)
            mufa16_1 += f * nv(food.lipids?.mufa16_1); mufa17_1 += f * nv(food.lipids?.mufa17_1)
            mufa18_1 += f * nv(food.lipids?.mufa18_1); mufa20_1 += f * nv(food.lipids?.mufa20_1)
            mufa22_1 += f * nv(food.lipids?.mufa22_1); mufa24_1 += f * nv(food.lipids?.mufa24_1)

            // TFA
            tfa16_1_t += f * nv(food.lipids?.tfa16_1_t); tfa18_1_t += f * nv(food.lipids?.tfa18_1_t)
            tfa22_1_t += f * nv(food.lipids?.tfa22_1_t); tfa18_2_t += f * nv(food.lipids?.tfa18_2_t)

            // PUFA
            pufa18_2 += f * nv(food.lipids?.pufa18_2); pufa18_3 += f * nv(food.lipids?.pufa18_3)
            pufa18_4 += f * nv(food.lipids?.pufa18_4); pufa20_2 += f * nv(food.lipids?.pufa20_2)
            pufa20_3 += f * nv(food.lipids?.pufa20_3); pufa20_4 += f * nv(food.lipids?.pufa20_4)
            pufa20_5 += f * nv(food.lipids?.pufa20_5); pufa21_5 += f * nv(food.lipids?.pufa21_5)
            pufa22_4 += f * nv(food.lipids?.pufa22_4); pufa22_5 += f * nv(food.lipids?.pufa22_5)
            pufa22_6 += f * nv(food.lipids?.pufa22_6); pufa2_4  += f * nv(food.lipids?.pufa2_4)

            // Vitamins
            vA        += f * nv(food.vitamins?.vitaminA_RAE)
            retinol   += f * nv(food.vitamins?.retinol)
            carotAlpha += f * nv(food.vitamins?.caroteneAlpha)
            carotBeta += f * nv(food.vitamins?.caroteneBeta)
            cryptoxBeta += f * nv(food.vitamins?.cryptoxanthinBeta)
            lutein    += f * nv(food.vitamins?.luteinZeaxanthin)
            lycopene  += f * nv(food.vitamins?.lycopene)
            b1        += f * nv(food.vitamins?.vitaminB1_Thiamin)
            b2        += f * nv(food.vitamins?.vitaminB2_Riboflavin)
            b3        += f * nv(food.vitamins?.vitaminB3_Niacin)
            b5        += f * nv(food.vitamins?.vitaminB5_PantothenicAcid)
            b6        += f * nv(food.vitamins?.vitaminB6)
            folateDFE += f * nv(food.vitamins?.folateDFE)
            folateFood += f * nv(food.vitamins?.folateFood)
            folateTotal += f * nv(food.vitamins?.folateTotal)
            folicAcid += f * nv(food.vitamins?.folicAcid)
            b12       += f * nv(food.vitamins?.vitaminB12)
            vC        += f * nv(food.vitamins?.vitaminC)
            vD        += f * nv(food.vitamins?.vitaminD)
            vE        += f * nv(food.vitamins?.vitaminE)
            vK        += f * nv(food.vitamins?.vitaminK)
            choline   += f * nv(food.vitamins?.choline)

            // Minerals
            calcium   += f * nv(food.minerals?.calcium)
            phosphorus += f * nv(food.minerals?.phosphorus)
            magnesium += f * nv(food.minerals?.magnesium)
            potassium += f * nv(food.minerals?.potassium)
            sodium    += f * nv(food.minerals?.sodium)
            iron      += f * nv(food.minerals?.iron)
            zinc      += f * nv(food.minerals?.zinc)
            copper    += f * nv(food.minerals?.copper)
            manganese += f * nv(food.minerals?.manganese)
            selenium  += f * nv(food.minerals?.selenium)
            fluoride  += f * nv(food.minerals?.fluoride)

            // Amino acids
            alanine   += f * nv(food.aminoAcids?.alanine)
            arginine  += f * nv(food.aminoAcids?.arginine)
            aspartic  += f * nv(food.aminoAcids?.asparticAcid)
            cystine   += f * nv(food.aminoAcids?.cystine)
            glutamic  += f * nv(food.aminoAcids?.glutamicAcid)
            glycine   += f * nv(food.aminoAcids?.glycine)
            histidine += f * nv(food.aminoAcids?.histidine)
            isoleucine += f * nv(food.aminoAcids?.isoleucine)
            leucine   += f * nv(food.aminoAcids?.leucine)
            lysine    += f * nv(food.aminoAcids?.lysine)
            methionine += f * nv(food.aminoAcids?.methionine)
            phenylalanine += f * nv(food.aminoAcids?.phenylalanine)
            proline   += f * nv(food.aminoAcids?.proline)
            threonine += f * nv(food.aminoAcids?.threonine)
            tryptophan += f * nv(food.aminoAcids?.tryptophan)
            tyrosine  += f * nv(food.aminoAcids?.tyrosine)
            valine    += f * nv(food.aminoAcids?.valine)
            serine    += f * nv(food.aminoAcids?.serine)
            hydroxyproline += f * nv(food.aminoAcids?.hydroxyproline)

            // Carb details
            starch    += f * nv(food.carbDetails?.starch)
            sucrose   += f * nv(food.carbDetails?.sucrose)
            glucose   += f * nv(food.carbDetails?.glucose)
            fructose  += f * nv(food.carbDetails?.fructose)
            lactose   += f * nv(food.carbDetails?.lactose)
            maltose   += f * nv(food.carbDetails?.maltose)
            galactose += f * nv(food.carbDetails?.galactose)

            // Sterols
            phytosterols  += f * nv(food.sterols?.phytosterols)
            betaSitosterol += f * nv(food.sterols?.betaSitosterol)
            campesterol   += f * nv(food.sterols?.campesterol)
            stigmasterol  += f * nv(food.sterols?.stigmasterol)
        }

        // --- pH на сместа ---
        var mixedPH: Nutrient? = nil
        if hPlusWeight > 0, hPlusSum > 0 {
            let hConc = hPlusSum / hPlusWeight
            let phValue = -log10(hConc)
            mixedPH = Nutrient(value: phValue, unit: "")
        }

        macros = MacroForm(
            carbohydrates: n(sumCarbs, "g"),
            protein:       n(sumProtein, "g"),
            fat:           n(sumFat, "g"),
            fiber:         n(sumFiber, "g"),
            totalSugars:   n(sumSugars, "g")
        )

        others = OtherForm(
            alcoholEthyl:  n(sumAlcohol, "g"),
            caffeine:      n(sumCaffeine, "mg"),
            theobromine:   n(sumTheobromine, "mg"),
            cholesterol:   n(sumCholesterol, "mg"),
            energyKcal:    n(sumEnergy, "kcal"),
            water:         n(sumWater, "g"),
            weightG:       totalGrams > 0 ? Nutrient(value: totalGrams, unit: "g") : nil,
            ash:           n(sumAsh, "g"),
            betaine:       n(sumBetaine, "mg"),
            alkalinityPH:  mixedPH    // <-- ТУК ВЕЧЕ Е СМЕСЕНИЯТ pH
        )

        lipids = LipidForm(
            totalSaturated:       n(sumSat, "g"),
            totalMonounsaturated: n(sumMono,"g"),
            totalPolyunsaturated: n(sumPoly,"g"),
            totalTrans:           n(sumTrans,"g"),
            totalTransMonoenoic:  n(sumTransMono,"g"),
            totalTransPolyenoic:  n(sumTransPoly,"g"),
            sfa4_0: n(sfa4,"g"), sfa6_0: n(sfa6,"g"), sfa8_0: n(sfa8,"g"),
            sfa10_0: n(sfa10,"g"), sfa12_0: n(sfa12,"g"), sfa13_0: n(sfa13,"g"),
            sfa14_0: n(sfa14,"g"), sfa15_0: n(sfa15,"g"), sfa16_0: n(sfa16,"g"),
            sfa17_0: n(sfa17,"g"), sfa18_0: n(sfa18,"g"), sfa20_0: n(sfa20,"g"),
            sfa22_0: n(sfa22,"g"), sfa24_0: n(sfa24,"g"),
            mufa14_1: n(mufa14_1,"g"), mufa15_1: n(mufa15_1,"g"), mufa16_1: n(mufa16_1,"g"),
            mufa17_1: n(mufa17_1,"g"), mufa18_1: n(mufa18_1,"g"), mufa20_1: n(mufa20_1,"g"),
            mufa22_1: n(mufa22_1,"g"), mufa24_1: n(mufa24_1,"g"),
            tfa16_1_t: n(tfa16_1_t,"g"), tfa18_1_t: n(tfa18_1_t,"g"),
            tfa22_1_t: n(tfa22_1_t,"g"), tfa18_2_t: n(tfa18_2_t,"g"),
            pufa18_2: n(pufa18_2,"g"), pufa18_3: n(pufa18_3,"g"), pufa18_4: n(pufa18_4,"g"),
            pufa20_2: n(pufa20_2,"g"), pufa20_3: n(pufa20_3,"g"), pufa20_4: n(pufa20_4,"g"),
            pufa20_5: n(pufa20_5,"g"), pufa21_5: n(pufa21_5,"g"),
            pufa22_4: n(pufa22_4,"g"), pufa22_5: n(pufa22_5,"g"), pufa22_6: n(pufa22_6,"g"),
            pufa2_4:  n(pufa2_4,"g")
        )

        vitamins = VitaminForm(
            vitaminA_RAE: n(vA,"µg"),
            retinol: n(retinol,"µg"),
            caroteneAlpha: n(carotAlpha,"µg"),
            caroteneBeta:  n(carotBeta,"µg"),
            cryptoxanthinBeta: n(cryptoxBeta,"µg"),
            luteinZeaxanthin:  n(lutein,"µg"),
            lycopene: n(lycopene,"µg"),
            vitaminB1_Thiamin: n(b1,"mg"),
            vitaminB2_Riboflavin: n(b2,"mg"),
            vitaminB3_Niacin: n(b3,"mg"),
            vitaminB5_PantothenicAcid: n(b5,"mg"),
            vitaminB6: n(b6,"mg"),
            folateDFE: n(folateDFE,"µg"),
            folateFood: n(folateFood,"µg"),
            folateTotal: n(folateTotal,"µg"),
            folicAcid: n(folicAcid,"µg"),
            vitaminB12: n(b12,"µg"),
            vitaminC: n(vC,"mg"),
            vitaminD: n(vD,"µg"),
            vitaminE: n(vE,"mg"),
            vitaminK: n(vK,"µg"),
            choline: n(choline,"mg")
        )

        minerals = MineralForm(
            calcium: n(calcium,"mg"),
            phosphorus: n(phosphorus,"mg"),
            magnesium: n(magnesium,"mg"),
            potassium: n(potassium,"mg"),
            sodium: n(sodium,"mg"),
            iron: n(iron,"mg"),
            zinc: n(zinc,"mg"),
            copper: n(copper,"mg"),
            manganese: n(manganese,"mg"),
            selenium: n(selenium,"µg"),
            fluoride: n(fluoride,"µg")
        )

        aminoAcids = AminoAcidsForm(
            alanine: n(alanine,"g"), arginine: n(arginine,"g"), asparticAcid: n(aspartic,"g"),
            cystine: n(cystine,"g"), glutamicAcid: n(glutamic,"g"), glycine: n(glycine,"g"),
            histidine: n(histidine,"g"), isoleucine: n(isoleucine,"g"), leucine: n(leucine,"g"),
            lysine: n(lysine,"g"), methionine: n(methionine,"g"), phenylalanine: n(phenylalanine,"g"),
            proline: n(proline,"g"), threonine: n(threonine,"g"), tryptophan: n(tryptophan,"g"),
            tyrosine: n(tyrosine,"g"), valine: n(valine,"g"), serine: n(serine,"g"),
            hydroxyproline: n(hydroxyproline,"g")
        )

        carbDetails = CarbDetailsForm(
            starch: n(starch,"g"), sucrose: n(sucrose,"g"), glucose: n(glucose,"g"),
            fructose: n(fructose,"g"), lactose: n(lactose,"g"), maltose: n(maltose,"g"),
            galactose: n(galactose,"g")
        )

        sterols = SterolsForm(
            phytosterols: n(phytosterols,"mg"),
            betaSitosterol: n(betaSitosterol,"mg"),
            campesterol: n(campesterol,"mg"),
            stigmasterol: n(stigmasterol,"mg")
        )
    }

    
    private func recalcTags() {
        guard !selectedIng.isEmpty else {
            selectedCategories = []; selectedDiets = []; selectedAllergens = []
            return
        }
        var catUnion = Set<FoodCategory.ID>()
        var dietsIntersection: Set<Diet.ID>? = nil
        var allUnion = Set<Allergen.ID>()

        for item in selectedIng.keys {
            let itemDiets = Set(item.diets?.map(\.id) ?? [])
            catUnion.formUnion(item.category?.map(\.id) ?? [])
            allUnion.formUnion(item.allergens?.map(\.id) ?? [])
            if dietsIntersection == nil {
                dietsIntersection = itemDiets
            } else {
                dietsIntersection?.formIntersection(itemDiets)
            }
        }
        selectedCategories = catUnion
        selectedDiets = dietsIntersection ?? []
        selectedAllergens = allUnion
    }

    static func aggregatedTags(for item: FoodItem) -> (categories: Set<FoodCategory.ID>, diets: Set<Diet.ID>, allergens: Set<Allergen.ID>) {
        guard let links = item.ingredients, !links.isEmpty else {
            return (Set(item.category?.map(\.id) ?? []), Set(item.diets?.map(\.id) ?? []), Set(item.allergens?.map(\.id) ?? []))
        }
        var catUnion = Set<FoodCategory.ID>()
        var dietsIntersection: Set<Diet.ID>? = nil
        var allUnion = Set<Allergen.ID>()

        for link in links {
            guard let food = link.food else { continue }
            let itemDiets = Set(food.diets?.map(\.id) ?? [])
            catUnion.formUnion(food.category?.map(\.id) ?? [])
            allUnion.formUnion(food.allergens?.map(\.id) ?? [])
            if dietsIntersection == nil {
                dietsIntersection = itemDiets
            } else {
                dietsIntersection?.formIntersection(itemDiets)
            }
        }
        return (catUnion, dietsIntersection ?? [], allUnion)
    }

    // MARK: - Nutrient Row Generation
    private var macroGrid: some View {
        let editableRows: [NutrientRow] = [
            .init(label: "Energy", unit: "kcal", field: nutBinding(\.energyKcal, state: $others, unit: "kcal")),
            NutrientRow(label: "Carbs", unit: "g", field: nutBinding(\.carbohydrates, state: $macros, unit: "g")),
            NutrientRow(label: "Protein", unit: "g", field: nutBinding(\.protein, state: $macros, unit: "g")),
            NutrientRow(label: "Fat", unit: "g", field: nutBinding(\.fat, state: $macros, unit: "g"))
        ]
        return VStack(spacing: 12) {
            nutrientGrid([editableRows[0]])
            HStack {
                Text("Weight / serving")
                Spacer()
                HStack(spacing: 4) {
                    let grams = others.weightG?.value ?? 0
                    let displayValue = isImperial ? UnitConversion.gToOz(grams) : grams
                    Text(UnitConversion.formatDecimal(displayValue))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    Text(servingUnit)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            nutrientGrid(Array(editableRows.dropFirst()))
        }
    }
    
    private var lipidTotalsGrid: some View {
        VStack(spacing: 12) {
            Text("Totals")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            nutrientGrid([
                .init(label: "Sat. fat",           unit: "g", field: nutBinding(\.totalSaturated,        state: $lipids)),
                .init(label: "Mono-unsat.",        unit: "g", field: nutBinding(\.totalMonounsaturated,  state: $lipids)),
                .init(label: "Poly-unsat.",        unit: "g", field: nutBinding(\.totalPolyunsaturated,  state: $lipids)),
                .init(label: "Trans fat",          unit: "g", field: nutBinding(\.totalTrans,            state: $lipids)),
                .init(label: "Trans monoenoic",    unit: "g", field: nutBinding(\.totalTransMonoenoic,   state: $lipids)),
                .init(label: "Trans polyenoic",    unit: "g", field: nutBinding(\.totalTransPolyenoic,   state: $lipids)),
            ])
        }
    }
    private var lipidSFAGrid: some View {
        VStack(spacing: 8) {
            Text("Saturated Fatty Acids (SFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            nutrientGrid([
                .init(label: "C4:0",  unit: "g", field: nutBinding(\.sfa4_0,  state: $lipids)),
                .init(label: "C6:0",  unit: "g", field: nutBinding(\.sfa6_0,  state: $lipids)),
                .init(label: "C8:0",  unit: "g", field: nutBinding(\.sfa8_0,  state: $lipids)),
                .init(label: "C10:0", unit: "g", field: nutBinding(\.sfa10_0, state: $lipids)),
                .init(label: "C12:0", unit: "g", field: nutBinding(\.sfa12_0, state: $lipids)),
                .init(label: "C13:0", unit: "g", field: nutBinding(\.sfa13_0, state: $lipids)),
                .init(label: "C14:0", unit: "g", field: nutBinding(\.sfa14_0, state: $lipids)),
                .init(label: "C15:0", unit: "g", field: nutBinding(\.sfa15_0, state: $lipids)),
                .init(label: "C16:0", unit: "g", field: nutBinding(\.sfa16_0, state: $lipids)),
                .init(label: "C17:0", unit: "g", field: nutBinding(\.sfa17_0, state: $lipids)),
                .init(label: "C18:0", unit: "g", field: nutBinding(\.sfa18_0, state: $lipids)),
                .init(label: "C20:0", unit: "g", field: nutBinding(\.sfa20_0, state: $lipids)),
                .init(label: "C22:0", unit: "g", field: nutBinding(\.sfa22_0, state: $lipids)),
                .init(label: "C24:0", unit: "g", field: nutBinding(\.sfa24_0, state: $lipids)),
            ])
        }
    }
    private var lipidMUFAGrid: some View {
        VStack(spacing: 8) {
            Text("Monounsaturated Fatty Acids (MUFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            nutrientGrid([
                .init(label: "C14:1", unit: "g", field: nutBinding(\.mufa14_1, state: $lipids)),
                .init(label: "C15:1", unit: "g", field: nutBinding(\.mufa15_1, state: $lipids)),
                .init(label: "C16:1", unit: "g", field: nutBinding(\.mufa16_1, state: $lipids)),
                .init(label: "C17:1", unit: "g", field: nutBinding(\.mufa17_1, state: $lipids)),
                .init(label: "C18:1", unit: "g", field: nutBinding(\.mufa18_1, state: $lipids)),
                .init(label: "C20:1", unit: "g", field: nutBinding(\.mufa20_1, state: $lipids)),
                .init(label: "C22:1", unit: "g", field: nutBinding(\.mufa22_1, state: $lipids)),
                .init(label: "C24:1", unit: "g", field: nutBinding(\.mufa24_1, state: $lipids)),
            ])
        }
    }
    private var lipidTFAGrid: some View {
        VStack(spacing: 8) {
            Text("Trans Fatty Acids (TFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            nutrientGrid([
                .init(label: "C16:1 t", unit: "g", field: nutBinding(\.tfa16_1_t, state: $lipids)),
                .init(label: "C18:1 t", unit: "g", field: nutBinding(\.tfa18_1_t, state: $lipids)),
                .init(label: "C22:1 t", unit: "g", field: nutBinding(\.tfa22_1_t, state: $lipids)),
                .init(label: "C18:2 t", unit: "g", field: nutBinding(\.tfa18_2_t, state: $lipids)),
            ])
        }
    }
    private var lipidPUFAGrid: some View {
        VStack(spacing: 8) {
            Text("Polyunsaturated Fatty Acids (PUFA)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            nutrientGrid([
                .init(label: "C18:2", unit: "g", field: nutBinding(\.pufa18_2, state: $lipids)),
                .init(label: "C18:3", unit: "g", field: nutBinding(\.pufa18_3, state: $lipids)),
                .init(label: "C18:4", unit: "g", field: nutBinding(\.pufa18_4, state: $lipids)),
                .init(label: "C20:2", unit: "g", field: nutBinding(\.pufa20_2, state: $lipids)),
                .init(label: "C20:3", unit: "g", field: nutBinding(\.pufa20_3, state: $lipids)),
                .init(label: "C20:4", unit: "g", field: nutBinding(\.pufa20_4, state: $lipids)),
                .init(label: "C20:5", unit: "g", field: nutBinding(\.pufa20_5, state: $lipids)),
                .init(label: "C21:5", unit: "g", field: nutBinding(\.pufa21_5, state: $lipids)),
                .init(label: "C22:4", unit: "g", field: nutBinding(\.pufa22_4, state: $lipids)),
                .init(label: "C22:5", unit: "g", field: nutBinding(\.pufa22_5, state: $lipids)),
                .init(label: "C22:6", unit: "g", field: nutBinding(\.pufa22_6, state: $lipids)),
                .init(label: "C2:4",  unit: "g", field: nutBinding(\.pufa2_4,  state: $lipids)),
            ])
        }
    }

    private var otherGrid: some View {
        nutrientGrid([
            .init(label: "Alcohol", unit: "g",  field: nutBinding(\.alcoholEthyl, state: $others, unit: "g")),
            .init(label: "Caffeine", unit: "mg", field: nutBinding(\.caffeine, state: $others, unit: "mg")),
            .init(label: "Theobromine", unit: "mg", field: nutBinding(\.theobromine, state: $others, unit: "mg")),
            .init(label: "Cholesterol", unit: "mg", field: nutBinding(\.cholesterol, state: $others, unit: "mg")),
            .init(label: "Water", unit: "g", field: nutBinding(\.water, state: $others, unit: "g")),
            .init(label: "Ash", unit: "g", field: nutBinding(\.ash, state: $others, unit: "g")),
            .init(label: "Betaine", unit: "mg", field: nutBinding(\.betaine, state: $others, unit: "mg")),
            .init(label: "Fiber", unit: "g", field: nutBinding(\.fiber, state: $macros, unit: "g")),
            .init(label: "Total sugars", unit: "g", field: nutBinding(\.totalSugars, state: $macros, unit: "g")),
            .init(label: "pH", unit: "", field: nutBinding(\.alkalinityPH, state: $others, unit: ""))
        ])
    }
    
    private func splitRows(_ rows: [NutrientRow], priorityNames: Set<String>) -> (prio: [NutrientRow], other: [NutrientRow]) {
        (rows.filter { priorityNames.contains($0.label) }, rows.filter { !priorityNames.contains($0.label) })
    }
    private func label(for vitamin: Vitamin) -> String { vitaminLabelById[vitamin.id] ?? vitamin.name }
    private func label(for mineral: Mineral) -> String { mineralLabelById[mineral.id] ?? mineral.name }

    private func vitaminRows() -> [NutrientRow] {
        [.init(label: "Vit A", unit: "µg RAE", field: nutBinding(\.vitaminA_RAE, state: $vitamins, unit: "µg")),
         .init(label: "Retinol", unit: "µg", field: nutBinding(\.retinol, state: $vitamins, unit: "µg")),
         .init(label: "α-Carotene", unit: "µg", field: nutBinding(\.caroteneAlpha, state: $vitamins, unit: "µg")),
         .init(label: "β-Carotene", unit: "µg", field: nutBinding(\.caroteneBeta, state: $vitamins, unit: "µg")),
         .init(label: "β-Cryptoxanthin", unit: "µg", field: nutBinding(\.cryptoxanthinBeta, state: $vitamins, unit: "µg")),
         .init(label: "Lutein + Zeax.", unit: "µg", field: nutBinding(\.luteinZeaxanthin, state: $vitamins, unit: "µg")),
         .init(label: "Lycopene", unit: "µg", field: nutBinding(\.lycopene, state: $vitamins, unit: "µg")),
         .init(label: "B1 Thiamin", unit: "mg", field: nutBinding(\.vitaminB1_Thiamin, state: $vitamins, unit: "mg")),
         .init(label: "B2 Riboflavin", unit: "mg", field: nutBinding(\.vitaminB2_Riboflavin, state: $vitamins, unit: "mg")),
         .init(label: "B3 Niacin", unit: "mg", field: nutBinding(\.vitaminB3_Niacin, state: $vitamins, unit: "mg")),
         .init(label: "B5 Pant. acid", unit: "mg", field: nutBinding(\.vitaminB5_PantothenicAcid, state: $vitamins, unit: "mg")),
         .init(label: "B6", unit: "mg", field: nutBinding(\.vitaminB6, state: $vitamins, unit: "mg")),
         .init(label: "Folate DFE", unit: "µg", field: nutBinding(\.folateDFE, state: $vitamins, unit: "µg")),
         .init(label: "Folate food", unit: "µg", field: nutBinding(\.folateFood, state: $vitamins, unit: "µg")),
         .init(label: "Folate total", unit: "µg", field: nutBinding(\.folateTotal, state: $vitamins, unit: "µg")),
         .init(label: "Folic acid", unit: "µg", field: nutBinding(\.folicAcid, state: $vitamins, unit: "µg")),
         .init(label: "B12", unit: "µg", field: nutBinding(\.vitaminB12, state: $vitamins, unit: "µg")),
         .init(label: "Vit C", unit: "mg", field: nutBinding(\.vitaminC, state: $vitamins, unit: "mg")),
         .init(label: "Vit D", unit: "µg", field: nutBinding(\.vitaminD, state: $vitamins, unit: "µg")),
         .init(label: "Vit E", unit: "mg", field: nutBinding(\.vitaminE, state: $vitamins, unit: "mg")),
         .init(label: "Vit K", unit: "µg", field: nutBinding(\.vitaminK, state: $vitamins, unit: "µg")),
         .init(label: "Choline", unit: "mg", field: nutBinding(\.choline, state: $vitamins, unit: "mg"))]
    }

    private func mineralRows() -> [NutrientRow] {
        [.init(label: "Calcium", unit: "mg", field: nutBinding(\.calcium, state: $minerals, unit: "mg")),
         .init(label: "Phosphorus", unit: "mg", field: nutBinding(\.phosphorus, state: $minerals, unit: "mg")),
         .init(label: "Magnesium", unit: "mg", field: nutBinding(\.magnesium, state: $minerals, unit: "mg")),
         .init(label: "Potassium", unit: "mg", field: nutBinding(\.potassium, state: $minerals, unit: "mg")),
         .init(label: "Sodium", unit: "mg", field: nutBinding(\.sodium, state: $minerals, unit: "mg")),
         .init(label: "Iron", unit: "mg", field: nutBinding(\.iron, state: $minerals, unit: "mg")),
         .init(label: "Zinc", unit: "mg", field: nutBinding(\.zinc, state: $minerals, unit: "mg")),
         .init(label: "Copper", unit: "mg", field: nutBinding(\.copper, state: $minerals, unit: "mg")),
         .init(label: "Manganese", unit: "mg", field: nutBinding(\.manganese, state: $minerals, unit: "mg")),
         .init(label: "Selenium", unit: "µg", field: nutBinding(\.selenium, state: $minerals, unit: "µg")),
         .init(label: "Fluoride", unit: "µg", field: nutBinding(\.fluoride, state: $minerals, unit: "µg"))]
    }
    
    private func aminoAcidRows() -> [NutrientRow] {
        [.init(label: "Alanine", unit: "g", field: nutBinding(\.alanine, state: $aminoAcids)),
         .init(label: "Arginine", unit: "g", field: nutBinding(\.arginine, state: $aminoAcids)),
         .init(label: "Aspartic Acid", unit: "g", field: nutBinding(\.asparticAcid, state: $aminoAcids)),
         .init(label: "Cystine", unit: "g", field: nutBinding(\.cystine, state: $aminoAcids)),
         .init(label: "Glutamic Acid", unit: "g", field: nutBinding(\.glutamicAcid, state: $aminoAcids)),
         .init(label: "Glycine", unit: "g", field: nutBinding(\.glycine, state: $aminoAcids)),
         .init(label: "Histidine", unit: "g", field: nutBinding(\.histidine, state: $aminoAcids)),
         .init(label: "Isoleucine", unit: "g", field: nutBinding(\.isoleucine, state: $aminoAcids)),
         .init(label: "Leucine", unit: "g", field: nutBinding(\.leucine, state: $aminoAcids)),
         .init(label: "Lysine", unit: "g", field: nutBinding(\.lysine, state: $aminoAcids)),
         .init(label: "Methionine", unit: "g", field: nutBinding(\.methionine, state: $aminoAcids)),
         .init(label: "Phenylalanine", unit: "g", field: nutBinding(\.phenylalanine, state: $aminoAcids)),
         .init(label: "Proline", unit: "g", field: nutBinding(\.proline, state: $aminoAcids)),
         .init(label: "Threonine", unit: "g", field: nutBinding(\.threonine, state: $aminoAcids)),
         .init(label: "Tryptophan", unit: "g", field: nutBinding(\.tryptophan, state: $aminoAcids)),
         .init(label: "Tyrosine", unit: "g", field: nutBinding(\.tyrosine, state: $aminoAcids)),
         .init(label: "Valine", unit: "g", field: nutBinding(\.valine, state: $aminoAcids)),
         .init(label: "Serine", unit: "g", field: nutBinding(\.serine, state: $aminoAcids)),
         .init(label: "Hydroxyproline", unit: "g", field: nutBinding(\.hydroxyproline, state: $aminoAcids))]
    }
    
    private func carbDetailRows() -> [NutrientRow] {
        [.init(label: "Starch", unit: "g", field: nutBinding(\.starch, state: $carbDetails)),
         .init(label: "Sucrose", unit: "g", field: nutBinding(\.sucrose, state: $carbDetails)),
         .init(label: "Glucose", unit: "g", field: nutBinding(\.glucose, state: $carbDetails)),
         .init(label: "Fructose", unit: "g", field: nutBinding(\.fructose, state: $carbDetails)),
         .init(label: "Lactose", unit: "g", field: nutBinding(\.lactose, state: $carbDetails)),
         .init(label: "Maltose", unit: "g", field: nutBinding(\.maltose, state: $carbDetails)),
         .init(label: "Galactose", unit: "g", field: nutBinding(\.galactose, state: $carbDetails))]
    }
    
    private func sterolRows() -> [NutrientRow] {
        [.init(label: "Phytosterols", unit: "mg", field: nutBinding(\.phytosterols, state: $sterols, unit: "mg")),
         .init(label: "Beta-Sitosterol", unit: "mg", field: nutBinding(\.betaSitosterol, state: $sterols, unit: "mg")),
         .init(label: "Campesterol", unit: "mg", field: nutBinding(\.campesterol, state: $sterols, unit: "mg")),
         .init(label: "Stigmasterol", unit: "mg", field: nutBinding(\.stigmasterol, state: $sterols, unit: "mg"))]
    }
    
    private func dismissKeyboardAndSearch() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    
    private var selectedNutrientItem: SelectableNutrient? {
        guard let id = selectedNutrientID else { return nil }
        return allSelectableNutrients.first { $0.id == id }
    }
    
    private var filterChipItems: [SelectableNutrient] {
        guard let profile else { return allSelectableNutrients }
        let priorityVitIDs = Set(profile.priorityVitamins.map { "vit_" + $0.id })
        let priorityMinIDs = Set(profile.priorityMinerals.map { "min_" + $0.id })
        let allPriorityIDs = priorityVitIDs.union(priorityMinIDs)

        let (priority, other) = allSelectableNutrients.reduce(into: ([SelectableNutrient](), [SelectableNutrient]())) { result, nutrient in
            if allPriorityIDs.contains(nutrient.id) { result.0.append(nutrient) }
            else { result.1.append(nutrient) }
        }
        return priority + other
    }
    
    private var allSelectableNutrients: [SelectableNutrient] {
        var items: [SelectableNutrient] = []
        items.append(contentsOf: allVitamins.map { SelectableNutrient(id: "vit_\($0.id)", label: $0.abbreviation) })
        items.append(contentsOf: allMinerals.map { SelectableNutrient(id: "min_\($0.id)", label: $0.symbol) })
        return items.sorted { $0.label < $1.label }
    }

    private func nutrientColor(for id: String) -> Color {
        if id.starts(with: "vit_"), let vitamin = allVitamins.first(where: { "vit_\($0.id)" == id }) { return Color(hex: vitamin.colorHex) }
        if id.starts(with: "min_"), let mineral = allMinerals.first(where: { "min_\($0.id)" == id }) { return Color(hex: mineral.colorHex) }
        return .gray
    }
    
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
                // ТУК: използвайте aiIsPressed
                DispatchQueue.main.async { self.aiIsPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.aiIsDragging = true
                }
            }
            .onEnded { value in
                // ТУК: използвайте aiIsPressed
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
              alertMsg = "Please enter a name for the recipe first."
              showAlert = true
              return
          }
          
          focusedField = nil
          hasUserMadeEdits = false // Reset edit tracking before starting AI job
          
          if #available(iOS 26.0, *) {
              triggerAIGenerationToast()

              if let newJob = aiManager.startRecipeGeneration(
                  for: self.profile!,
                  recipeName: self.name,
                  jobType: .recipeGeneration
              ) {
                  self.runningGenerationJobID = newJob.id
              } else {
                  alertMsg = "Could not start AI recipe generation job."
                  showAlert = true
                  toastTimer?.invalidate()
                  toastTimer = nil
                  withAnimation { showAIGenerationToast = false }
              }
          } else {
              alertMsg = "AI recipe generation requires iOS 26 or newer."
              showAlert = true
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
        // ТУК: използвайте aiIsPressed
        let scale = aiIsDragging ? 1.15 : (aiIsPressed ? 0.9 : 1.0)

        Image(systemName: "sparkles")
            .font(.title2)
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .frame(width: 60, height: 60)
            .glassCardStyle(cornerRadius: 32)
            .scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aiIsDragging)
            // ТУК: използвайте aiIsPressed
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

    @available(iOS 26.0, *)
    private func populateFromCompletedJob(jobID: UUID) async {
        guard let job = (aiManager.jobs.first { $0.id == jobID }),
              let resultData = job.resultData else {
            alertMsg = "Could not find completed job data."
            showAlert = true
            runningGenerationJobID = nil
            return
        }

        let decoder = JSONDecoder()
        // --- НАЧАЛО НА ПРОМЯНАТА (1/2) ---
        guard let payload = try? decoder.decode(ResolvedRecipeResponseDTO.self, from: resultData) else {
            alertMsg = "Could not decode the generated recipe data."
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(job)
            return
        }
        // --- КРАЙ НА ПРОМЯНАТА (1/2) ---

        print("🧭 populateFromCompletedJob: decoded DTO")
        print("   • Description preview: \(payload.description.prefix(120))\(payload.description.count > 120 ? "..." : "")")
        print("   • Prep time: \(payload.prepTimeMinutes) min")
        print("   • Ingredients (DTO): \(payload.ingredients.count)")

        var newIngredients: [FoodItem: Double] = [:]
        var unresolvedCount = 0

        // --- НАЧАЛО НА ПРОМЯНАТА (2/2) ---
        // Извличаме всички нужни елементи наведнъж
        let foodItemIDs = payload.ingredients.map { $0.foodItemID }
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { foodItemIDs.contains($0.id) })
        let fetchedItems = (try? ctx.fetch(descriptor)) ?? []
        let itemMap = Dictionary(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
        
        for entry in payload.ingredients {
            if let fi = itemMap[entry.foodItemID] {
                newIngredients[fi, default: 0.0] += entry.grams
            } else {
                unresolvedCount += 1
            }
        }
        // --- КРАЙ НА ПРОМЯНАТА (2/2) ---

        print("   • Resolved FoodItems: \(newIngredients.count)")
        if unresolvedCount > 0 {
            print("   • Unresolved entries: \(unresolvedCount)")
        }

        await MainActor.run {
            withAnimation(.easeInOut) {
                self.itemDescription = payload.description
                self.prepTimeTxt = String(max(5, min(240, payload.prepTimeMinutes)))
                self.selectedIng = newIngredients
                self.ingredientTextValues = Dictionary(
                    uniqueKeysWithValues: newIngredients.map { (item, grams) in
                        let displayValue = isImperial ? UnitConversion.gToOz(grams) : grams
                        return (item.id, GlobalState.formatDecimalString(String(displayValue)))
                    }
                )
            }
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
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation {
            showAIGenerationToast = true
        }

        let totalDuration = 5.0
        let updateInterval = 0.1
        let progressIncrement = updateInterval / totalDuration

        toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                self.toastProgress = min(1.0, self.toastProgress + progressIncrement)
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

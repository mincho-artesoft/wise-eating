import SwiftData
import SwiftUI
import PhotosUI

@MainActor
struct ProfileEditorView: View {
    // MARK: – Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @ObservedObject private var effectManager = EffectManager.shared

    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]
    @Query(sort: \Diet.name) private var allDiets: [Diet]

    // MARK: – View Models & State
    private let calVM = CalendarViewModel.shared
    @State private var path = NavigationPath()
    @State private var draftMeal: Meal?
    @State private var meals: [Meal]
    
    @State private var trainings: [Training]
    @State private var draftTraining: Training?

    // MARK: – Profile Fields
    @State private var name: String
    @State private var birthday: Date?
    @State private var gender: String
    @State private var weight: String
    @State private var height: String
    @State private var headCircumference: String
    @State private var goal: Goal?
    @State private var activityLevelSTR: String = ActivityLevel.sedentary.description

    @State private var activityLevel: ActivityLevel
    @State private var isPregnant: Bool
    @State private var isLactating: Bool
    @State private var hasSeparateStorage: Bool = false

    // MARK: – Selections
    @State private var selectedVitIDs: Set<Vitamin.ID>
    @State private var selectedMinIDs: Set<Mineral.ID>
    @State private var selectedDiets: Set<Diet.ID>
    @State private var selectedAllergens: Set<Allergen.ID>
    @State private var selectedSportIDs: Set<Sport.ID>

    // MARK: – Photo
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var photoData: Data?

    // MARK: – Error
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    // MARK: – Drop-Down Menu
    enum OpenMenu { case none, vitamin, mineral, diet, allergen, sport, goal }
    @State private var openMenu: OpenMenu = .none
    @State private var buttonFrames: [OpenMenu: CGRect] = [:]

    private enum Field: Hashable {
        case name, weight, height, headCircumference
    }
    @FocusState private var focusedField: Field?

    private var ageInYears: Int? {
        guard let bday = birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: bday, to: Date()).year
    }

    private struct MenuButtonPreference: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: [OpenMenu: CGRect] = [:]
        static func reduce(value: inout [OpenMenu: CGRect], nextValue: () -> [OpenMenu: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    // MARK: – Input Properties
    var profile: Profile?
    var isEmpty: Bool
    var isInit: Bool
    var selectedTabRoot: Binding<Int>?
    var oldSelectedTab: Int?
    @Binding var navBarIsHiden: Bool
    @Binding var isProfilesDrawerVisible: Bool
    @Binding var menuState: MenuState
    let onDismiss: (Profile?) -> Void

    // MARK: – Init
    init(profile: Profile? = nil,
         isEmpty: Bool = false,
         isInit: Bool = false,
         selectedTabRoot: Binding<Int>? = nil,
         oldSelectedTab: Int? = nil,
         navBarIsHiden: Binding<Bool>,
         isProfilesDrawerVisible: Binding<Bool>,
         menuState: Binding<MenuState>,
         onDismiss: @escaping (Profile?) -> Void) {
        self.profile = profile
        self.isEmpty = isEmpty
        self.isInit = isInit
        self.selectedTabRoot = selectedTabRoot
        self.oldSelectedTab = oldSelectedTab
        self._navBarIsHiden = navBarIsHiden
        self._isProfilesDrawerVisible = isProfilesDrawerVisible
        self._menuState = menuState
        self.onDismiss = onDismiss

        if let p = profile {
            _name = State(initialValue: p.name)
            _birthday = State(initialValue: p.birthday)
            _gender = State(initialValue: p.gender)
            _weight = State(initialValue: GlobalState.measurementSystem == "Imperial" ? UnitConversion.formatDecimal(UnitConversion.kgToLbs(p.weight)) : UnitConversion.formatDecimal(p.weight))
            _height = State(initialValue: GlobalState.measurementSystem == "Imperial" ? UnitConversion.formatDecimal(UnitConversion.cmToInches(p.height)) : UnitConversion.formatDecimal(p.height))
            _goal = State(initialValue: p.goal)
            _meals = State(initialValue: p.meals)
            _trainings = State(initialValue: p.trainings)
            _activityLevel = State(initialValue: p.activityLevel)
            _isPregnant = State(initialValue: p.isPregnant)
            _isLactating = State(initialValue: p.isLactating)
            _photoData = State(initialValue: p.photoData)
            _selectedVitIDs = State(initialValue: Set(p.priorityVitamins.map(\.id)))
            _selectedMinIDs = State(initialValue: Set(p.priorityMinerals.map(\.id)))
            _selectedDiets = State(initialValue: Set(p.diets.map(\.id)))
            _selectedAllergens = State(initialValue: Set(p.allergens.map(\.id)))
            _hasSeparateStorage = State(initialValue: p.hasSeparateStorage)
            _selectedSportIDs = State(initialValue: Set(p.sports.map(\.id)))

            if p.age < 2,
               let latestRecord = p.weightHeightHistory.sorted(by: { $0.date > $1.date }).first,
               let hc = latestRecord.headCircumference {
                _headCircumference = State(initialValue: GlobalState.measurementSystem == "Imperial" ? UnitConversion.formatDecimal(UnitConversion.cmToInches(hc)) : UnitConversion.formatDecimal(hc))
            } else {
                _headCircumference = State(initialValue: "")
            }
        } else {
            _name = State(initialValue: "")
            _birthday = State(initialValue: nil)
            _gender = State(initialValue: "Male")
            _weight = State(initialValue: "")
            _height = State(initialValue: "")
            _headCircumference = State(initialValue: "")
            _goal = State(initialValue: .generalFitness)
            _meals = State(initialValue: Meal.defaultMeals())
            _trainings = State(initialValue: Training.defaultTrainings())
            _activityLevel = State(initialValue: .sedentary)
            _isPregnant = State(initialValue: false)
            _isLactating = State(initialValue: false)
            _photoData = State(initialValue: nil)
            _selectedVitIDs = State(initialValue: [])
            _selectedMinIDs = State(initialValue: [])
            _selectedDiets = State(initialValue: [])
            _selectedAllergens = State(initialValue: [])
            _hasSeparateStorage = State(initialValue: false)
            _selectedSportIDs = State(initialValue: [])
        }
    }

 var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { rootGeo in
                ZStack(alignment: .topLeading) {
                    ThemeBackgroundView().ignoresSafeArea()

                    VStack(spacing: 0) {
                        customToolbar
                        
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 24) {
                                    personalSection
                                    goalSection
                                    vitaminsSection
                                    mineralsSection
                                    dietsSection
                                    allergensSection
                                    sportsSection
                                    mealsSection
                                    trainingsSection
                                    settingsSection
                                }
                                .padding(.vertical)
                                Spacer(minLength: 150)
                            }
                            .onChange(of: focusedField) { _, newFocus in
                                if newFocus == nil {
                                    formatAllInputs()
                                }

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
                                        .init(color: effectManager.currentGlobalAccentColor, location: isInit ? 1 : 0.9),
                                        .init(color: .clear, location: isInit ? 2 : 0.95)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .background(Color.clear)
                            .navigationDestination(item: $draftMeal) { meal in
                                MealEditorView(meal: meal, isNew: meal.name.isEmpty, onSave: save)
                            }
                            .navigationDestination(item: $draftTraining) { training in
                                TrainingEditorView(training: training, isNew: training.name.isEmpty, onSave: saveTrainingFromEditor)
                            }
                            .alert("Error", isPresented: $showErrorAlert) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                if let msg = errorMessage { Text(msg) }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .zIndex(0)

                    if openMenu != .none {
                        bottomSheetPanel
                            .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .toolbar(.hidden, for: .navigationBar)
                .coordinateSpace(name: "root")
                .onPreferenceChange(MenuButtonPreference.self) { buttonFrames = $0 }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            navBarIsHiden = true
        }
    }
 
 // MARK: - Custom Toolbar
 @ViewBuilder
 private var customToolbar: some View {
     HStack {
         HStack {
             Button("Cancel") {
                 if isEmpty {
                     selectedTabRoot?.wrappedValue = oldSelectedTab ?? 1
                 } else {
                     onDismiss(nil)
                 }
             }
         }
         .padding(.horizontal, 10)
         .padding(.vertical, 5)
         .glassCardStyle(cornerRadius: 20)
         .opacity(isInit ? 0 : 1)
         
         Spacer()

         Text(profile == nil ? "Add Profile" : "Edit Profile")
             .font(.headline)
             .foregroundColor(effectManager.currentGlobalAccentColor)

         Spacer()
         
         let isSaveDisabled = name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              UnitConversion.parseDecimal(weight) == nil ||
                              UnitConversion.parseDecimal(height) == nil ||
                              birthday == nil
         HStack {
             Button("Save", action: saveProfile)
                 .disabled(isSaveDisabled)
         }
         .padding(.horizontal, 10)
         .padding(.vertical, 5)
         .glassCardStyle(cornerRadius: 20)
         .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
     }
     .foregroundColor(effectManager.currentGlobalAccentColor)
     .padding(.top, 10)
 }
 
 private var personalSection: some View {
       VStack(alignment: .leading, spacing: 8) {
           Text("Personal Information")
               .font(.headline)
               .foregroundStyle(effectManager.currentGlobalAccentColor)

           VStack(alignment: .leading, spacing: 12) {
               HStack(alignment: .top, spacing: 16) {
                   photoPicker
                   VStack(alignment: .leading, spacing: 12) {
                       
                       StyledLabeledPicker(label: "Name", isRequired: true) {
                           TextField("", text: $name, prompt: Text("John Appleseed").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                               .font(.system(size: 16))
                               .focused($focusedField, equals: .name)
                               .disableAutocorrection(true)
                       }
                       .id(Field.name)
                       
                       HStack(spacing: 12) {
                           StyledLabeledPicker(label: "Height (\(GlobalState.measurementSystem == "Imperial" ? "in" : "cm"))", isRequired: true) {
                               ConfigurableTextField(
                                   title: GlobalState.measurementSystem == "Imperial" ? "70" : "175",
                                   value: $height,
                                   type: .decimal,
                                   placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                                   textAlignment: .leading,
                                   focused: $focusedField,
                                   fieldIdentifier: .height
                               )
                               .font(.system(size: 16))
                               .onChange(of: height) { _, newValue in
                                   let maxHeightCm = 300.0
                                   guard let displayedValue = UnitConversion.parseDecimal(newValue) else { return }
                                   let currentHeightCm = GlobalState.measurementSystem == "Imperial" ? UnitConversion.inchesToCm(displayedValue) : displayedValue
                                   
                                   if currentHeightCm > maxHeightCm {
                                       let clampedDisplayedValue = GlobalState.measurementSystem == "Imperial" ? UnitConversion.cmToInches(maxHeightCm) : maxHeightCm
                                       DispatchQueue.main.async {
                                           self.height = UnitConversion.formatDecimal(clampedDisplayedValue)
                                       }
                                   }
                                }
                           }
                           .id(Field.height)
                           
                           StyledLabeledPicker(label: "Weight (\(GlobalState.measurementSystem == "Imperial" ? "lbs" : "kg"))", isRequired: true) {
                               ConfigurableTextField(
                                   title: GlobalState.measurementSystem == "Imperial" ? "155" : "70.5",
                                   value: $weight,
                                   type: .decimal,
                                   placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                                   textAlignment: .leading,
                                   focused: $focusedField,
                                   fieldIdentifier: .weight
                               )
                               .font(.system(size: 16))
                               .onChange(of: weight) { _, newValue in
                                   let maxWeightKg = 500.0
                                   guard let displayedValue = UnitConversion.parseDecimal(newValue) else { return }
                                   let currentWeightKg = GlobalState.measurementSystem == "Imperial" ? UnitConversion.lbsToKg(displayedValue) : displayedValue
                                   
                                   if currentWeightKg > maxWeightKg {
                                       let clampedDisplayedValue = GlobalState.measurementSystem == "Imperial" ? UnitConversion.kgToLbs(maxWeightKg) : maxWeightKg
                                       DispatchQueue.main.async { self.weight = UnitConversion.formatDecimal(clampedDisplayedValue) }
                                   }
                               }
                           }
                           .id(Field.weight)
                       }
                   }
               }
               .padding(.vertical, 4)

               VStack(spacing: 12) {
                   HStack {
                       StyledLabeledPicker(label: "Sex", isRequired: true) {
                           Menu {
                               Picker("Select Gender", selection: $gender) {
                                   ForEach(genders, id: \.self, content: Text.init)
                               }
                               .onChange(of: gender) { _, new in
                                   if new.lowercased().hasPrefix("m") { isPregnant = false; isLactating = false }
                               }
                           } label: {
                               Text(gender)
                                   .font(.system(size: 16))
                                   .frame(maxWidth: .infinity, alignment: .leading)
                                   .contentShape(Rectangle())
                                   .foregroundColor(effectManager.currentGlobalAccentColor)
                           }
                       }
                       
                       birthdayPicker
                   }
                   
                   if ageInYears ?? 2 < 2 {
                        StyledLabeledPicker(label: "Head Circ. (\(GlobalState.measurementSystem == "Imperial" ? "in" : "cm"))") {
                           ConfigurableTextField(
                               title: GlobalState.measurementSystem == "Imperial" ? "16" : "40",
                               value: $headCircumference,
                               type: .decimal,
                               placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                               textAlignment: .leading,
                               focused: $focusedField,
                               fieldIdentifier: .headCircumference
                           )
                           .font(.system(size: 16))
                        }
                        .id(Field.headCircumference)
                   }
                   
                   if ageInYears ?? 2 >= 2 {
                       StyledLabeledPicker(label: "Activity Level", isRequired: true) {
                           Menu {
                               Picker("Activity Level", selection: $activityLevel) {
                                   ForEach(ActivityLevel.allCases) { level in
                                       Text(level.description).tag(level)
                                   }
                               }
                           } label: {
                               Text(activityLevel.description)
                                   .font(.system(size: 16))
                                   .frame(maxWidth: .infinity, alignment: .leading)
                                   .contentShape(Rectangle())
                                   .foregroundColor(effectManager.currentGlobalAccentColor)
                           }
                       }
                       if ageInYears ?? 2 >= 14 {
                           if gender.lowercased().hasPrefix("f") {
                               Toggle("Pregnant", isOn: $isPregnant).padding(.horizontal, 4).foregroundColor(effectManager.currentGlobalAccentColor)
                               Toggle("Lactating", isOn: $isLactating).padding(.horizontal, 4).foregroundColor(effectManager.currentGlobalAccentColor)
                           }
                       }
                   }
               }
           }
           .padding()
           .glassCardStyle(cornerRadius: 20)
       }
   }

 private var goalSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Main Goal")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
         
         Button {
             withAnimation {
                 openMenu = .goal
             }
         } label: {
             HStack {
                 if let selectedGoal = goal {
                     Image(systemName: selectedGoal.systemImageName)
                     Text(selectedGoal.title)
                 } else {
                     Text("Select a Goal")
                 }
                 Spacer()
                 Image(systemName: "chevron.up.chevron.down")
             }
             .foregroundColor(effectManager.currentGlobalAccentColor)
             .padding()
             .frame(maxWidth: .infinity, alignment: .leading)          // ← заема цялата ширина
             .contentShape(RoundedRectangle(cornerRadius: 20))          // ← цялата карта е кликаема
             .glassCardStyle(cornerRadius: 20)
         }
         .buttonStyle(.plain)
     }
 }
 
 private var settingsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Data Management")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         VStack(alignment: .leading, spacing: 12) {
             Toggle(isOn: $hasSeparateStorage) {
                 VStack(alignment: .leading, spacing: 2) {
                     Text("Separate Storage & Lists")
                     Text("When on, this profile will have its own private storage and shopping lists. Otherwise, it will use the shared global data.")
                         .font(.caption)
                         .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                 }
             }
             .padding(.horizontal, 4)
             .foregroundColor(effectManager.currentGlobalAccentColor)
         }
         .padding()
         .glassCardStyle(cornerRadius: 20)
     }
 }

 private var vitaminsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Priority Vitamins")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
         
         tagPicker(label: "Vitamins", selection: $selectedVitIDs, items: allVitamins, menu: .vitamin) { vitamin in
             "\(vitamin.name) (\(vitamin.abbreviation))"
         }
         .glassCardStyle(cornerRadius: 20)
     }
 }

 private var mineralsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Priority Minerals")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         tagPicker(label: "Minerals", selection: $selectedMinIDs, items: allMinerals, menu: .mineral) { mineral in
             "\(mineral.name) (\(mineral.symbol))"
         }
         .glassCardStyle(cornerRadius: 20)
     }
 }

 private var dietsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Diets")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         tagPicker(label: "Diets", selection: $selectedDiets, items: allDiets, menu: .diet) { diet in
             diet.name
         }
         .glassCardStyle(cornerRadius: 20)
     }
 }

 private var allergensSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Allergens")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         tagPicker(label: "Allergens", selection: $selectedAllergens, items: Allergen.allCases, menu: .allergen) { allergen in
             allergen.rawValue
         }
         .glassCardStyle(cornerRadius: 20)
     }
 }
 
 private var mealsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Meals")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         VStack(spacing: 12) {
             VStack(spacing: 12) {
                 ForEach(meals) { meal in
                     mealRow(for: meal)
                 }
             }
             .padding()
             .glassCardStyle(cornerRadius: 20)
             
             HStack{
                 Button(action: addMeal) {
                     Label("Add Meal", systemImage: "plus")
                         .frame(maxWidth: .infinity, alignment: .center)
                         .contentShape(Rectangle())
                 }
                 .foregroundStyle(effectManager.currentGlobalAccentColor)
                 .buttonStyle(.plain)
             }
             .padding()
             .glassCardStyle(cornerRadius: 20)
         }
     }
     .onAppear(perform: sortMealsIfNeeded)
     .onChange(of: meals) { _,_ in sortMealsIfNeeded() }
 }
 
 private var photoPicker: some View {
     let imageData = photoData
     let color = effectManager.currentGlobalAccentColor.opacity(0.6)

     return PhotosPicker(selection: $selectedPhoto, matching: .images) {
         Group {
             if let data = imageData, let ui = UIImage(data: data) {
                 Image(uiImage: ui).resizable().scaledToFill()
             } else {
                 Image(systemName: "person.crop.circle.fill")
                     .resizable()
                     .aspectRatio(contentMode: .fit)
                     .symbolRenderingMode(.hierarchical)
                     .foregroundColor(color)
             }
         }
         .frame(width: 120, height: 120).clipShape(Circle())
     }
     .buttonStyle(.plain)
     .onChange(of: selectedPhoto) { _, newItem in Task {
         if let data = try? await newItem?.loadTransferable(type: Data.self) {
             await MainActor.run { photoData = data }
         }
     }}
     .padding(.leading, -4)
 }
 
 private var birthdayPicker: some View {
     StyledLabeledPicker(label: "Birthday", isRequired: true) {
         ZStack(alignment: .leading) {
             
             Group {
                 if let date = birthday {
                     Text(date, format: .dateTime.day().month().year())
                 } else {
                     Label { Text("Select date") } icon: { Image(systemName: "calendar").foregroundColor(effectManager.currentGlobalAccentColor) }.lineLimit(1)

                 }
             }
             .padding(.horizontal, 4)
             .foregroundColor(effectManager.currentGlobalAccentColor)
             .allowsHitTesting(false)
             
             DatePicker(
                 "",
                 selection: birthdayBinding,
                 in: ...Date(),
                 displayedComponents: .date
             )
             .labelsHidden()
             .opacity(0.02)
         }
         .font(.system(size: 16))
     }
 }
 
 private func mealRow(for meal: Meal) -> some View {
     HStack(alignment: .firstTextBaseline) {
         Text(meal.name)
             .lineLimit(1)
             .frame(maxWidth: .infinity, alignment: .leading)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
             .layoutPriority(1)

         Text("\(meal.startTime.formatted(date: .omitted, time: .shortened)) – \(meal.endTime.formatted(date: .omitted, time: .shortened))")
             .lineLimit(1)
             .font(.system(size: 15))
             .minimumScaleFactor(0.8)
             .frame(width: 150, alignment: .trailing)
             .truncationMode(.tail)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
             .layoutPriority(0)
         
         Button { remove(meal) } label: {
             Image(systemName: "xmark.circle.fill")
                 .symbolRenderingMode(.palette)
                 .foregroundStyle(effectManager.currentGlobalAccentColor, effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2))
                 .font(.title3)
         }
         .buttonStyle(.plain)
         .frame(width: 30)
     }
     .contentShape(Rectangle())
     .onTapGesture { draftMeal = meal; path.append(meal) }
 }
 
 private func formatAllInputs() {
     if let currentWeightDisplay = UnitConversion.parseDecimal(weight) {
         let weightKg = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.lbsToKg(currentWeightDisplay) : currentWeightDisplay
         let clampedWeightKg = min(max(0, weightKg), 500.0)
         let finalDisplayWeight = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.kgToLbs(clampedWeightKg) : clampedWeightKg
         weight = UnitConversion.formatDecimal(finalDisplayWeight)
     }

     if let currentHeightDisplay = UnitConversion.parseDecimal(height) {
         let heightCm = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.inchesToCm(currentHeightDisplay) : currentHeightDisplay
         let clampedHeightCm = min(max(0, heightCm), 300.0)
         let finalDisplayHeight = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.cmToInches(clampedHeightCm) : clampedHeightCm
         height = UnitConversion.formatDecimal(finalDisplayHeight)
     }

     if let currentHeadCircumferenceDisplay = UnitConversion.parseDecimal(headCircumference) {
         let headCircumferenceCm = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.inchesToCm(currentHeadCircumferenceDisplay) : currentHeadCircumferenceDisplay
         let clampedHeadCircumferenceCm = min(max(0, headCircumferenceCm), 100.0)
         let finalDisplayHeadCircumference = (GlobalState.measurementSystem == "Imperial") ? UnitConversion.cmToInches(clampedHeadCircumferenceCm) : clampedHeadCircumferenceCm
         headCircumference = UnitConversion.formatDecimal(finalDisplayHeadCircumference)
     }
 }

 private func addMeal() {
     draftMeal = Meal(name: "", startTime: Date(), endTime: Date().addingTimeInterval(3600))
     path.append(draftMeal!)
 }
 
 private func geometryReader(for menu: OpenMenu) -> some View {
     GeometryReader { proxy in
         Color.clear.preference(key: MenuButtonPreference.self, value: [menu: proxy.frame(in: .named("root"))])
     }
 }

 private func save(_ updated: Meal) {
     if let idx = meals.firstIndex(where: { $0.id == updated.id }) {
         meals[idx].name = updated.name
         meals[idx].startTime = updated.startTime
         meals[idx].endTime = updated.endTime
         meals[idx].reminderMinutes = updated.reminderMinutes
         sortMealsIfNeeded()
         return
     }
     if updated.modelContext == nil {
         modelContext.insert(updated)
         try? modelContext.save()
     }
     meals.append(updated)
     sortMealsIfNeeded()
 }

 private func remove(_ meal: Meal) {
     if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
         meals.remove(at: idx)
     }
 }

 @MainActor
 private func saveProfile() {
     formatAllInputs()
     
     ensureMealsInserted()
     ensureTrainingsInserted()
     
     guard let w_display = UnitConversion.parseDecimal(weight),
           let h_display = UnitConversion.parseDecimal(height) else {
         showError("Please enter valid numbers for weight and height.")
         return
     }
     
     let weightInKg = GlobalState.measurementSystem == "Imperial" ? UnitConversion.lbsToKg(w_display) : w_display
     let heightInCm = GlobalState.measurementSystem == "Imperial" ? UnitConversion.inchesToCm(h_display) : h_display
     
     let headCircumferenceCm = UnitConversion.parseDecimal(headCircumference).map {
         GlobalState.measurementSystem == "Imperial" ? UnitConversion.inchesToCm($0) : $0
     }

     guard !meals.isEmpty else {
         showError("Please add at least one meal.")
         return
     }
     guard meals.allSatisfy({ $0.endTime > $0.startTime }) else {
         showError("Every meal must have an end time after its start time.")
         return
     }
     guard let validBirthday = birthday else {
         showError("Please select a birthday.")
         return
     }
     
     let chosenVitamins = allVitamins.filter { selectedVitIDs.contains($0.id) }
     let chosenMinerals = allMinerals.filter { selectedMinIDs.contains($0.id) }
     let chosenDiets = allDiets.filter { selectedDiets.contains($0.id) }
     let chosenAllergens = selectedAllergens.compactMap { Allergen(rawValue: $0) }
     let chosenSports = Sport.allCases.filter { selectedSportIDs.contains($0.id) }
     
     let activeProfile: Profile
     if let p = profile {
         let weightChanged = abs(p.weight - weightInKg) > 0.01
         let heightChanged = abs(p.height - heightInCm) > 0.1
         
         let latestRecord = p.weightHeightHistory.sorted { $0.date > $1.date }.first
         let headCircumferenceChanged = headCircumferenceCm != latestRecord?.headCircumference

         if weightChanged || heightChanged || (headCircumferenceChanged && ageInYears ?? 2 < 2) {
             let newRecord = WeightHeightRecord(date: Date(), weight: weightInKg, height: heightInCm, headCircumference: headCircumferenceCm)
             p.weightHeightHistory.append(newRecord)
         }

         p.name = name; p.birthday = validBirthday; p.gender = gender; p.weight = weightInKg
         p.height = heightInCm; p.goal = goal; p.meals = meals; p.trainings = trainings; p.activityLevel = activityLevel
         p.isPregnant = isPregnant; p.isLactating = isLactating; p.priorityVitamins = chosenVitamins
         p.priorityMinerals = chosenMinerals; p.diets = chosenDiets; p.allergens = chosenAllergens
         p.photoData = photoData; p.hasSeparateStorage = hasSeparateStorage; p.updatedAt = Date()
         p.sports = chosenSports
         
         activeProfile = p
     } else {
         let newProfile = Profile(
             name: name,
             birthday: validBirthday,
             gender: gender,
             weight: weightInKg,
             height: heightInCm,
             goal: goal,
             meals: meals,
             trainings: trainings,
             sports: chosenSports,
             activityLevel: activityLevel,
             isPregnant: isPregnant,
             isLactating: isLactating,
             priorityVitamins: chosenVitamins,
             priorityMinerals: chosenMinerals,
             diets: chosenDiets,
             allergens: chosenAllergens,
             photoData: photoData,
             hasSeparateStorage: hasSeparateStorage
         )
         let initialRecord = WeightHeightRecord(date: Date(), weight: weightInKg, height: heightInCm, headCircumference: headCircumferenceCm)
         newProfile.weightHeightHistory.append(initialRecord)
         
         modelContext.insert(newProfile)
         activeProfile = newProfile
     }
     
     Task { @MainActor in
         guard await calVM.requestCalendarAccessIfNeeded() else {
             showError("Calendar access is required to manage profile data and settings.")
             return
         }
         
         calVM.createOrUpdateCalendar(for: activeProfile)
         await calVM.createOrUpdateShoppingListCalendar(for: activeProfile, context: modelContext)
         
         do {
             try modelContext.save()
             onDismiss(activeProfile)
         } catch {
             showError("Failed to save profile: \(error.localizedDescription)")
         }
     }
 }
 
 private func ensureMealsInserted() {
     for meal in meals where meal.modelContext == nil {
         modelContext.insert(meal)
     }
 }
 
 private var trainingsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Workouts")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)

         VStack(spacing: 12) {
             VStack(spacing: 12) {
                 ForEach(trainings) { training in
                     trainingRow(for: training)
                 }
             }
             .padding()
             .glassCardStyle(cornerRadius: 20)
             
             HStack{
                 Button(action: addTraining) {
                     Label("Add Workout", systemImage: "plus")
                         .frame(maxWidth: .infinity, alignment: .center)
                         .contentShape(Rectangle())
                 }
                 .foregroundStyle(effectManager.currentGlobalAccentColor)
                 .buttonStyle(.plain)
             }
             .padding()
             .glassCardStyle(cornerRadius: 20)
         }
     }
     .onAppear(perform: sortTrainingsIfNeeded)
     .onChange(of: trainings) { _,_ in sortTrainingsIfNeeded() }
 }

 private func trainingRow(for training: Training) -> some View {
     HStack(alignment: .firstTextBaseline) {
         Text(training.name)
             .lineLimit(1)
             .frame(maxWidth: .infinity, alignment: .leading)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
             .layoutPriority(1)

         Text("\(training.startTime.formatted(date: .omitted, time: .shortened)) – \(training.endTime.formatted(date: .omitted, time: .shortened))")
             .lineLimit(1)
             .font(.system(size: 15))
             .minimumScaleFactor(0.8)
             .frame(width: 150, alignment: .trailing)
             .truncationMode(.tail)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
             .layoutPriority(0)
         
         Button { remove(training) } label: {
             Image(systemName: "xmark.circle.fill")
                 .symbolRenderingMode(.palette)
                 .foregroundStyle(effectManager.currentGlobalAccentColor, effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2))
                 .font(.title3)
         }
         .buttonStyle(.plain)
         .frame(width: 30)
     }
     .contentShape(Rectangle())
     .onTapGesture { draftTraining = training; path.append(training) }
 }
 
 private func addTraining() {
     draftTraining = Training(name: "", startTime: Date(), endTime: Date().addingTimeInterval(3600))
     path.append(draftTraining!)
 }
 
 private func saveTrainingFromEditor(_ updated: Training) {
     if let idx = trainings.firstIndex(where: { $0.id == updated.id }) {
         trainings[idx].name = updated.name
         trainings[idx].startTime = updated.startTime
         trainings[idx].endTime = updated.endTime
         trainings[idx].reminderMinutes = updated.reminderMinutes
         sortTrainingsIfNeeded()
         return
     }
     if updated.modelContext == nil {
         modelContext.insert(updated)
         try? modelContext.save()
     }
     trainings.append(updated)
     sortTrainingsIfNeeded()
 }

 private func remove(_ training: Training) {
     if let idx = trainings.firstIndex(where: { $0.id == training.id }) {
         trainings.remove(at: idx)
     }
 }

 private func sortTrainingsIfNeeded() {
     let sorted = trainings.sorted(by: trainingOrder)
     if sorted != trainings { trainings = sorted }
 }

    private var trainingOrder: (Training, Training) -> Bool {
        { a, b in
            let aStart = secondsSinceMidnight(a.startTime)
            let bStart = secondsSinceMidnight(b.startTime)

            if aStart != bStart { return aStart < bStart }

            let aEnd = secondsSinceMidnight(a.endTime)
            let bEnd = secondsSinceMidnight(b.endTime)

            if aEnd != bEnd { return aEnd < bEnd }

            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

 
 private func ensureTrainingsInserted() {
     for training in trainings where training.modelContext == nil {
         modelContext.insert(training)
     }
 }
 
 private var sportsSection: some View {
     VStack(alignment: .leading, spacing: 8) {
         Text("Favorite Sports")
             .font(.headline)
             .foregroundStyle(effectManager.currentGlobalAccentColor)
         
         tagPicker(label: "Sports", selection: $selectedSportIDs, items: Sport.allCases.sorted { $0.rawValue < $1.rawValue }, menu: .sport) { sport in
             sport.rawValue
         }
         .glassCardStyle(cornerRadius: 20)
     }
 }
 private func showError(_ msg: String) {
     errorMessage = msg
     showErrorAlert = true
 }

 private func sortMealsIfNeeded() {
     let sorted = meals.sorted(by: mealOrder)
     if sorted != meals { meals = sorted }
 }

    private var mealOrder: (Meal, Meal) -> Bool {
        { a, b in
            let aStart = secondsSinceMidnight(a.startTime)
            let bStart = secondsSinceMidnight(b.startTime)

            if aStart != bStart { return aStart < bStart }

            let aEnd = secondsSinceMidnight(a.endTime)
            let bEnd = secondsSinceMidnight(b.endTime)

            if aEnd != bEnd { return aEnd < bEnd }

            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

 private var birthdayBinding: Binding<Date> {
     Binding<Date>( get: { (birthday ?? Calendar.current.date(byAdding: .year, value: -30, to: .now))! }, set: { birthday = $0 })
 }
 
 private let genders = ["Male", "Female"]

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
                         withAnimation {
                             openMenu = .none
                         }
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
         case .vitamin:
             dropdownMenu(selection: $selectedVitIDs, items: allVitamins) { vitamin in
                 "\(vitamin.name) (\(vitamin.abbreviation))"
             }
         case .mineral:
             dropdownMenu(selection: $selectedMinIDs, items: allMinerals) { mineral in
                 "\(mineral.name) (\(mineral.symbol))"
             }
         case .diet:
             dropdownMenu(selection: $selectedDiets, items: allDiets, label: { $0.name })
         case .allergen:
             dropdownMenu(selection: $selectedAllergens, items: Allergen.allCases, label: { $0.rawValue })
         case .sport:
             dropdownMenu(selection: $selectedSportIDs, items: Sport.allCases.sorted(by: { $0.rawValue < $1.rawValue }), label: { $0.rawValue })
         case .goal:
             GoalSelectionView(selectedGoal: $goal, isStyle: true)
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
     menu: OpenMenu,
     itemLabel: @escaping (I) -> String
 ) -> some View {
         MultiSelectButton(selection: selection,
                           items: items,
                           label: itemLabel,
                           prompt: "Select \(label)",
                           isExpanded: openMenu == menu)
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
 
 private func hideKeyboard() {
     UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
 }
    
    fileprivate func secondsSinceMidnight(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
    }

}

extension ProfileEditorView.OpenMenu {
 var title: String {
     switch self {
     case .vitamin: return "Vitamins"
     case .mineral: return "Minerals"
     case .diet: return "Diets"
     case .allergen: return "Allergens"
     case .sport: return "Sports"
     case .goal: return "Main Goal"
     case .none: return ""
     }
 }
}

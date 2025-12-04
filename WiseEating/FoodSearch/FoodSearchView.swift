import SwiftUI
import SwiftData

/// The public entry point.
struct FoodSearchView: View {
    @Environment(\.modelContext) private var modelContext
    
    // ✅ НОВО: Приемаме профил (може да е nil, ако няма контекст)
    var profile: Profile? = nil
    
    var body: some View {
        FoodSearchViewContent(modelContainer: modelContext.container, profile: profile)
    }
}

/// The internal implementation containing the StateObject and UI Logic.
private struct FoodSearchViewContent: View {
    // MARK: - Dependencies
    @StateObject private var engine: SmartFoodSearch3
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - State
    @State private var searchText = ""
    @State private var selectedFilters: Set<NutrientType> = []
    @State private var debounceTask: Task<Void, Never>?
    
    // --- NEW: Search Mode State ---
    @State private var searchMode: SmartFoodSearch3.SearchMode? = nil
    
    // --- NEW: State for special filters ---
    @State private var isFavoritesModeActive = false
    @State private var showRecipesOnly = false
    @State private var showMenusOnly = false
    
    // Quick filter extra state
    @State private var isPhQuickFilterOn: Bool = false
    @State private var quickAgeFilterMonths: Double? = nil
    
    // ✅ НОВО: Запазваме профила
    let profile: Profile?
    
    // ✅ НОВО: Избрани храни (изключени от резултатите в engine)
    @State private var selectedFoodIDs: Set<Int> = []
    @State private var selectedFoods: [FoodItem] = []
    
    // MARK: - Quick Filter Model
    private enum QuickFilterChip: Hashable {
        case nutrient(NutrientType)
        case ph
        case age
    }
    
    // MARK: - Configuration
    private let macroFilters: [NutrientType] = [.energy, .protein, .carbs, .totalFat, .fiber, .totalSugar]
    private let vitaminFilters: [NutrientType] = [.vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin, .pantothenicAcid, .vitaminB6, .vitaminB12, .folateTotal]
    private let mineralFilters: [NutrientType] = [.calcium, .iron, .magnesium, .phosphorus, .potassium, .sodium, .zinc, .copper, .manganese, .selenium]
    
    private var nutrientQuickFilters: [NutrientType] { macroFilters + vitaminFilters + mineralFilters }
    private var quickFilterChips: [QuickFilterChip] { nutrientQuickFilters.map { .nutrient($0) } + [.ph, .age] }
    
    // MARK: - Initializer
    init(modelContainer: ModelContainer, profile: Profile?) {
        _engine = StateObject(wrappedValue: SmartFoodSearch3(container: modelContainer))
        self.profile = profile
    }
    
    // MARK: - Main Body
    var body: some View {
        VStack(spacing: 12) {
            // --- Mode Selector above search bar ---
            modeSelectorView
            
            searchBarView
            filtersView
            contentView
        }
        .navigationTitle("Wise Eating")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if engine.displayedResults.isEmpty {
                engine.loadData()
            }
        }
    }
    
    // MARK: - Sub-Views
    
    // --- Mode Selector View ---
    private var modeSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SmartFoodSearch3.SearchMode.allCases) { mode in
                    let isSelected = (searchMode == mode)
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if searchMode == mode {
                                searchMode = nil // Deselect if already selected
                            } else {
                                searchMode = mode // Select new mode
                            }
                        }
                        triggerSearch() // Update results immediately
                    }) {
                        Text(mode.rawValue)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? effectManager.currentGlobalAccentColor : Color.clear
                            )
                            .foregroundColor(
                                isSelected
                                ? (effectManager.isLightRowTextColor ? .black : .white)
                                : effectManager.currentGlobalAccentColor
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: isSelected ? 0 : 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 44)
    }
    
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search (e.g. 'Tomato', 'Milk 2%', 'No Dairy')", text: $searchText)
                .onChange(of: searchText) { _, newValue in handleUserInput(newValue) }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !searchText.isEmpty {
                Button(action: { searchText = ""; handleUserInput("") }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var filtersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                // --- FAVORITES BUTTON ---
                Button(action: { toggleSpecialFilter(.favorites) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if isFavoritesModeActive {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Favorites")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFavoritesModeActive ? Color.yellow : Color.yellow.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(isFavoritesModeActive ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)

                // --- RECIPES BUTTON ---
                Button(action: { toggleSpecialFilter(.recipes) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if showRecipesOnly {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Recipes")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(showRecipesOnly ? Color.green : Color.green.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(showRecipesOnly ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)

                // --- MENUS BUTTON ---
                Button(action: { toggleSpecialFilter(.menus) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.clipboard")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if showMenusOnly {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Menus")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(showMenusOnly ? Color.blue : Color.blue.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(showMenusOnly ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)
                
                ForEach(quickFilterChips, id: \.self) { chip in
                    FilterButton(
                        title: title(for: chip),
                        isSelected: isChipSelected(chip)
                    ) {
                        toggleChip(chip)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 44)
    }
    
    private var contentView: some View {
        Group {
            if engine.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Indexing Database...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                resultsListView
            }
        }
    }
    
    private var resultsListView: some View {
        List {
            // ✅ Секция с избраните храни
            if !selectedFoods.isEmpty {
                Section("Selected") {
                    ForEach(selectedFoods, id: \.id) { food in
                        HStack {
                            Text(food.name)
                                .font(.body)
                            Spacer()
                            Button(role: .destructive) {
                                removeFromSelected(food)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            
            // ✅ Секция с резултатите от търсенето – директно от engine
            Section("Results") {
                ForEach(engine.displayedResults, id: \.id) { food in
                    FoodRowView(
                        food: food,
                        engine: engine
                    )
                    .contentShape(Rectangle()) // пълният ред да е tappable
                    .onTapGesture {
                        addToSelected(food)
                    }
                    .onAppear {
                        if food.id == engine.displayedResults.last?.id {
                            engine.loadMoreResults()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Selection Helpers
    
    private func addToSelected(_ food: FoodItem) {
        guard !selectedFoodIDs.contains(food.id) else { return }
        selectedFoodIDs.insert(food.id)
        selectedFoods.append(food)
        // ✅ Преизпълняваме търсенето, вече с новите изключени ID-та
        triggerSearch()
    }
    
    private func removeFromSelected(_ food: FoodItem) {
        selectedFoodIDs.remove(food.id)
        selectedFoods.removeAll { $0.id == food.id }
        // ✅ Когато махнем от селектираните, позволяваме да се върне в резултатите
        triggerSearch()
    }
    
    // MARK: - Logic Helpers
    
    private func handleUserInput(_ text: String) {
        debounceTask?.cancel()
        
        let callSearch = {
            self.engine.performSearch(
                query: text,
                activeFilters: self.selectedFilters,
                quickAgeMonths: self.quickAgeFilterMonths,
                forcePhDisplay: self.isPhQuickFilterOn,
                isFavoritesOnly: self.isFavoritesModeActive,
                isRecipesOnly: self.showRecipesOnly,
                isMenusOnly: self.showMenusOnly,
                searchMode: self.searchMode,
                profile: self.profile,
                excludedFoodIDs: self.selectedFoodIDs   // ✅ НОВО
            )
        }
        
        if text.isEmpty {
            debounceTask = Task {
                await MainActor.run { callSearch() }
            }
            return
        }
        
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            await MainActor.run { callSearch() }
        }
    }

    private func triggerSearch() {
        engine.performSearch(
            query: searchText,
            activeFilters: selectedFilters,
            quickAgeMonths: quickAgeFilterMonths,
            forcePhDisplay: isPhQuickFilterOn,
            isFavoritesOnly: isFavoritesModeActive,
            isRecipesOnly: showRecipesOnly,
            isMenusOnly: showMenusOnly,
            searchMode: searchMode,
            profile: self.profile,
            excludedFoodIDs: self.selectedFoodIDs   // ✅ НОВО
        )
    }

    // MARK: - Chip Helpers
    private enum SpecialFilter { case favorites, recipes, menus }

    private func toggleSpecialFilter(_ filter: SpecialFilter) {
        withAnimation(.easeInOut) {
            switch filter {
            case .favorites:
                isFavoritesModeActive.toggle()
            case .recipes:
                showRecipesOnly.toggle()
                if showRecipesOnly { showMenusOnly = false }
            case .menus:
                showMenusOnly.toggle()
                if showMenusOnly { showRecipesOnly = false }
            }
        }
        triggerSearch()
    }

    private func title(for chip: QuickFilterChip) -> String {
        switch chip {
        case .nutrient(let type): return SmartFoodSearch3.displayName(for: type)
        case .ph: return "pH"
        case .age:
            if let months = quickAgeFilterMonths {
                return (months >= 12) ? "Age \(Int(months / 12.0))y+" : "Age \(Int(months))m+"
            } else {
                return "Age"
            }
        }
    }
    
    private func isChipSelected(_ chip: QuickFilterChip) -> Bool {
        switch chip {
        case .nutrient(let n): return selectedFilters.contains(n)
        case .ph: return isPhQuickFilterOn
        case .age: return quickAgeFilterMonths != nil
        }
    }
    
    private func toggleChip(_ chip: QuickFilterChip) {
        switch chip {
        case .nutrient(let n):
            if selectedFilters.contains(n) { selectedFilters.remove(n) }
            else { selectedFilters.insert(n) }
        case .ph:
            isPhQuickFilterOn.toggle()
        case .age:
            quickAgeFilterMonths = (quickAgeFilterMonths == nil) ? 12.0 : nil
        }
        triggerSearch()
    }
    
    private func formatName(_ type: NutrientType) -> String {
        SmartFoodSearch3.displayName(for: type)
    }
}

// MARK: - Component: Food Row
private struct FoodRowView: View {
    let food: FoodItem
    @ObservedObject var engine: SmartFoodSearch3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(food.name).font(.body).foregroundColor(.primary)
                Spacer()
                
                // Възрастова група
                if food.minAgeMonths >= 0 {
                    let ageText = food.minAgeMonths >= 12
                        ? "\(food.minAgeMonths / 12)y+"
                        : "\(food.minAgeMonths)m+"
                    
                    Text(ageText)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.8))
                        .clipShape(Capsule())
                }

                Text("per 100g").font(.caption).foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if let age = engine.searchContext.activeAgeLimit {
                        Text("Age: \(age)").font(.caption2).padding(4).background(Color.green.opacity(0.1)).cornerRadius(4).foregroundColor(.green)
                    }
                    if engine.searchContext.isPhActive && food.ph > 0 {
                        Text("pH: \(String(format: "%.1f", food.ph))").font(.caption2).padding(4).background(phColor(food.ph).opacity(0.1)).cornerRadius(4).foregroundColor(phColor(food.ph))
                    }
                }
                
                // Алергени
                if let allergens = food.allergens, !allergens.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .padding(.top, 1)
                        Text(allergens.map { $0.name }.joined(separator: ", "))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
                
                // Диети
                if let diets = food.diets, !diets.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "leaf.circle.fill")
                            .padding(.top, 1)
                        Text(diets.map { $0.name }.joined(separator: ", "))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption2)
                    .foregroundColor(.green)
                }
            }
            
            if !engine.searchContext.displayNutrients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(engine.searchContext.displayNutrients, id: \.self) { nutrient in
                            if let result = engine.normalizedAndScaledValue(for: food, nutrient: nutrient) {
                                HStack(spacing: 2) {
                                    Text(formatName(nutrient) + ":").font(.caption).foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", result.value)) \(result.unit)").font(.caption).fontWeight(.bold).foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            } else {
                HStack {
                    if let calories = engine.normalizedAndScaledValue(for: food, nutrient: .energy) {
                        Text("Calories:").font(.caption).foregroundColor(.secondary)
                        Text("\(String(format: "%.0f", calories.value)) \(calories.unit)").font(.caption).fontWeight(.bold)
                    }
                    if let protein = engine.normalizedAndScaledValue(for: food, nutrient: .protein) {
                        Text("• Protein:").font(.caption).foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", protein.value))\(protein.unit)").font(.caption).fontWeight(.bold)
                    }
                    if let fat = engine.normalizedAndScaledValue(for: food, nutrient: .totalFat) {
                        Text("• Fat:").font(.caption).foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", fat.value))\(fat.unit)").font(.caption).fontWeight(.bold)
                    }
                    if let carbs = engine.normalizedAndScaledValue(for: food, nutrient: .carbs) {
                        Text("• Carbs:").font(.caption).foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", carbs.value))\(carbs.unit)").font(.caption).fontWeight(.bold)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func phColor(_ ph: Double) -> Color {
        if ph < 6.5 { return .red }
        if ph > 7.5 { return .blue }
        return .green
    }
    
    private func formatName(_ type: NutrientType) -> String {
        SmartFoodSearch3.displayName(for: type)
    }
}

// MARK: - Component: Filter Button
private struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
                )
        }
    }
}

import SwiftUI
import SwiftData

struct FoodSearchPanelView: View {
    // MARK: - Dependencies & Queries
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @StateObject private var smartSearch: SmartFoodSearch3
    private var externalNutrientSelection: Binding<String?>?
    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]
    
    // MARK: - Bindings & Callbacks
    @Binding var globalSearchText: String
    @Binding var isSearchFieldFocused: Bool
    let profile: Profile?
    let onSelectFood: (FoodItem) -> Void
    let onDismiss: () -> Void
    
    // MARK: - Configuration Parameters
    let searchMode: SmartFoodSearch3.SearchMode?
    let showFavoritesFilter: Bool
    let showRecipesFilter: Bool
    let showMenusFilter: Bool
    
    // Незадължителен текст за дясната част на хедъра
    let headerRightText: String?
    
    // Сет от ID-та на храни, които да НЕ се показват в резултатите
    let excludedFoodIDs: Set<Int>
    
    // MARK: - Internal State
    @State private var isFavoritesModeActive: Bool = false
    @State private var isRecipesModeActive: Bool = false
    @State private var isMenusModeActive: Bool = false
    
    @State private var selectedNutrientID: String? = nil
    
    // MARK: - Initializer
    init(
        globalSearchText: Binding<String>,
        isSearchFieldFocused: Binding<Bool>,
        profile: Profile?,
        searchMode: SmartFoodSearch3.SearchMode? = nil,
        showFavoritesFilter: Bool = true,
        showRecipesFilter: Bool = false,
        showMenusFilter: Bool = false,
        headerRightText: String? = nil,
        excludedFoodIDs: Set<Int> = [],
        // ✅ НОВО: Добавяме параметър с default nil
        selectedNutrientID: Binding<String?>? = nil,
        onSelectFood: @escaping (FoodItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._globalSearchText = globalSearchText
        self._isSearchFieldFocused = isSearchFieldFocused
        self.profile = profile
        self.onSelectFood = onSelectFood
        self.onDismiss = onDismiss
        
        self.searchMode = searchMode
        self.showFavoritesFilter = showFavoritesFilter
        self.showRecipesFilter = showRecipesFilter
        self.showMenusFilter = showMenusFilter
        self.headerRightText = headerRightText
        self.excludedFoodIDs = excludedFoodIDs
        
        // ✅ НОВО: Запазваме външния binding
        self.externalNutrientSelection = selectedNutrientID
        
        if let container = GlobalState.modelContext?.container {
            _smartSearch = StateObject(wrappedValue: SmartFoodSearch3(container: container))
        } else {
            fatalError("ModelContext not available.")
        }
    }
    
    // MARK: - Computed Properties
    
    // ✅ КОРЕКЦИЯТА Е ТУК:
    // Филтрираме резултатите локално веднага, преди да ги покажем.
    // Това премахва "премигването", докато енджинът обработва заявката асинхронно.
    private var displayedSearchResults: [FoodItem] {
        let results = smartSearch.displayedResults
        
        if excludedFoodIDs.isEmpty {
            return results
        } else {
            return results.filter { !excludedFoodIDs.contains($0.id) }
        }
    }
    
    private var selectedFilterName: String? {
        guard let id = selectedNutrientID else { return nil }
        switch id {
        case "protein": return "Protein"
        case "fat": return "Fat"
        case "carbohydrates": return "Carbohydrates"
        case "ph_low": return "pH Low ↑"
        case "ph_high": return "pH High ↓"
        case "ph_neutral": return "pH Neutral ≈"
        default: break
        }
        return allSelectableNutrients.first(where: { $0.id == id })?.label
    }
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed background
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { onDismiss() }
            } else {
                Color.white.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { onDismiss() }
            }
            
            VStack(spacing: 0) {
                
                // Header Section
                let handleContainerHeight: CGFloat = 35
                
                HStack {
                    // ЛЯВА ЧАСТ: Избран филтър
                    if let name = selectedFilterName {
                        Text("Selected: \(name)")
                            .font(.body)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // ДЯСНА ЧАСТ: Допълнителен текст
                    if let rightText = headerRightText {
                        Text(rightText)
                            .font(.body)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: handleContainerHeight)
                
                filterChipsView
                
                Divider()
                    .background(effectManager.currentGlobalAccentColor.opacity(0.2))
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if displayedSearchResults.isEmpty && !smartSearch.isLoading {
                            Text("No results found.")
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .padding(.top, 50)
                        } else {
                            ForEach(displayedSearchResults) { item in
                                SearchResultRow(
                                    item: item,
                                    smartSearch: smartSearch,
                                    onTap: { onSelectFood(item) }
                                )
                                .onAppear {
                                    // Зареждане на още резултати при скролване
                                    if item.id == smartSearch.displayedResults.last?.id {
                                        smartSearch.loadMoreResults()
                                    }
                                }
                                Divider()
                                    .padding(.horizontal)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                    }
                    Spacer(minLength: 150)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
            }
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light)
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(height: UIScreen.main.bounds.height * 0.55)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            smartSearch.loadData()
            if let externalVal = externalNutrientSelection?.wrappedValue {
                self.selectedNutrientID = externalVal
            }
            triggerSearch()
        }
        .onChange(of: selectedNutrientID) { _, newValue in
            externalNutrientSelection?.wrappedValue = newValue
            triggerSearch()
        }
        .onChange(of: smartSearch.isLoading) { _, isLoading in
            if !isLoading && smartSearch.displayedResults.isEmpty {
                triggerSearch()
            }
        }
        .onChange(of: isSearchFieldFocused) { _, isFocused in
            if isFocused { triggerSearch() }
        }
        .onChange(of: globalSearchText) { _, _ in triggerSearch() }
        .onChange(of: selectedNutrientID) { _, _ in triggerSearch() }
        .onChange(of: isFavoritesModeActive) { _, _ in triggerSearch() }
        .onChange(of: isRecipesModeActive) { _, _ in triggerSearch() }
        .onChange(of: isMenusModeActive) { _, _ in triggerSearch() }
    }
    
    @ViewBuilder
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if showFavoritesFilter {
                    Button(action: { withAnimation(.easeInOut) { isFavoritesModeActive.toggle() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").imageScale(.medium).font(.system(size: 13, weight: .semibold))
                            if isFavoritesModeActive { Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold)) }
                        }
                        .accessibilityLabel("Favorites")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isFavoritesModeActive ? Color.yellow : Color.yellow.opacity(0.6)).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: isFavoritesModeActive ? 3 : 0))
                    }.glassCardStyle(cornerRadius: 20).buttonStyle(.plain)
                }
                
                if showRecipesFilter {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isRecipesModeActive.toggle()
                            if isRecipesModeActive { isMenusModeActive = false }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle.portrait").imageScale(.medium).font(.system(size: 13, weight: .semibold))
                            if isRecipesModeActive { Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold)) }
                        }
                        .accessibilityLabel("Recipes").foregroundStyle(effectManager.currentGlobalAccentColor).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isRecipesModeActive ? Color.green : Color.green.opacity(0.6)).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: isRecipesModeActive ? 3 : 0))
                    }.glassCardStyle(cornerRadius: 20).buttonStyle(.plain)
                }
                
                if showMenusFilter {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isMenusModeActive.toggle()
                            if isMenusModeActive { isRecipesModeActive = false }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.clipboard").imageScale(.medium).font(.system(size: 13, weight: .semibold))
                            if isMenusModeActive { Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold)) }
                        }
                        .accessibilityLabel("Menus").foregroundStyle(effectManager.currentGlobalAccentColor).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMenusModeActive ? Color.blue : Color.blue.opacity(0.6)).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: isMenusModeActive ? 3 : 0))
                    }.glassCardStyle(cornerRadius: 20).buttonStyle(.plain)
                }
                
                filterChipButton(for: SelectableNutrient(id: "protein", label: "Protein"))
                filterChipButton(for: SelectableNutrient(id: "fat", label: "Fat"))
                filterChipButton(for: SelectableNutrient(id: "carbohydrates", label: "Carbohydrates"))
                
                ForEach(filterChipItems) { item in filterChipButton(for: item) }
                
                let phState = selectedNutrientID
                Button(action: {
                    withAnimation(.easeInOut) {
                        if phState == "ph_low" { selectedNutrientID = "ph_neutral" }
                        else if phState == "ph_neutral" { selectedNutrientID = "ph_high" }
                        else if phState == "ph_high" { selectedNutrientID = nil }
                        else { selectedNutrientID = "ph_low" }
                    }
                }) {
                    HStack(spacing: 6) {
                        if phState == "ph_low" { Text("pH Low ↑").font(.caption.weight(.semibold)) }
                        else if phState == "ph_high" { Text("pH High ↓").font(.caption.weight(.semibold)) }
                        else if phState == "ph_neutral" { Text("pH Neutral ≈").font(.caption.weight(.semibold)) }
                        else { Text("pH Sort").font(.caption.weight(.semibold)) }
                        
                        if phState == "ph_low" || phState == "ph_high" || phState == "ph_neutral" {
                            Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold))
                                .onTapGesture { withAnimation(.easeInOut) { selectedNutrientID = nil } }
                        }
                    }
                    .foregroundStyle(effectManager.currentGlobalAccentColor).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Group {
                        if phState == "ph_low" { Color.red.opacity(0.6) }
                        else if phState == "ph_high" { Color.blue.opacity(0.6) }
                        else if phState == "ph_neutral" { Color.green.opacity(0.6) }
                        else { effectManager.currentGlobalAccentColor.opacity(0.3) }
                    })
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(phState == "ph_low" ? .red : (phState == "ph_high" ? .blue : (phState == "ph_neutral" ? .green : .clear)), lineWidth: (phState == "ph_low" || phState == "ph_high" || phState == "ph_neutral") ? 2 : 0))
                }.glassCardStyle(cornerRadius: 20).buttonStyle(.plain)
            }
            .padding(.horizontal).padding(.vertical, 5)
        }
        .transition(.opacity.animation(.easeInOut))
    }
    
    @ViewBuilder
    private func filterChipButton(for item: SelectableNutrient) -> some View {
        let isSelected = (selectedNutrientID == item.id)
        let itemColor = nutrientColor(for: item.id)
        Button(action: { withAnimation(.easeInOut) { selectedNutrientID = isSelected ? nil : item.id } }) {
            HStack(spacing: 6) {
                Text(item.label).font(.caption.weight(.semibold))
                if isSelected { Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor).padding(.horizontal, 14).padding(.vertical, 8)
            .background(itemColor.opacity(0.6)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(itemColor, lineWidth: isSelected ? 2 : 0))
        }.glassCardStyle(cornerRadius: 20).buttonStyle(.plain)
    }
    
    private func triggerSearch() {
        var activeFilters: Set<NutrientType> = []
        if let id = selectedNutrientID, let type = getCorrectNutrientType(from: id) {
            activeFilters.insert(type)
        }
        var phSort: SmartFoodSearch3.PhSortOrder? = nil
        if selectedNutrientID == "ph_low" { phSort = .lowToHigh }
        else if selectedNutrientID == "ph_high" { phSort = .highToLow }
        else if selectedNutrientID == "ph_neutral" { phSort = .neutral }
        
        // Тук също подаваме excludedFoodIDs на енджина, за да може той да ги вземе предвид
        // при зареждането на нови страници, въпреки че основното филтриране го правим локално във View-то.
        smartSearch.performSearch(
            query: globalSearchText,
            activeFilters: activeFilters,
            isFavoritesOnly: isFavoritesModeActive,
            isRecipesOnly: isRecipesModeActive,
            isMenusOnly: isMenusModeActive,
            searchMode: self.searchMode,
            profile: self.profile,          
            excludedFoodIDs: self.excludedFoodIDs,
            phSortOrder: phSort
        )
    }
    
    private var filterChipItems: [SelectableNutrient] {
        guard let profile = profile else { return allSelectableNutrients }
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
        switch id {
        case "protein": return Color(hex: "#C9BFED")
        case "fat": return Color(hex: "#FFDAB3")
        case "carbohydrates": return Color(hex: "#A8D7FF")
        default: break
        }
        if id.starts(with: "vit_"), let vitamin = allVitamins.first(where: { "vit_\($0.id)" == id }) { return Color(hex: vitamin.colorHex) }
        if id.starts(with: "min_"), let mineral = allMinerals.first(where: { "min_\($0.id)" == id }) { return Color(hex: mineral.colorHex) }
        return .gray
    }
    
    private func getCorrectNutrientType(from chipID: String) -> NutrientType? {
        if let type = NutrientType.fromID(chipID) { return type }
        if chipID.hasPrefix("vit_") {
            let rawID = String(chipID.dropFirst(4))
            switch rawID {
            case "vitA": return .vitaminA; case "vitC": return .vitaminC; case "vitD": return .vitaminD; case "vitE": return .vitaminE; case "vitK": return .vitaminK; case "vitB1": return .thiamin; case "vitB2": return .riboflavin; case "vitB3": return .niacin; case "vitB5": return .pantothenicAcid; case "vitB6": return .vitaminB6; case "vitB12": return .vitaminB12; case "folateDFE": return .folateDFE; case "folateFood": return .folateFood; case "folateTotal": return .folateTotal; case "folicAcid": return .folicAcid; case "choline": return .choline; default: return nil
            }
        }
        if chipID.hasPrefix("min_") {
            let rawID = String(chipID.dropFirst(4))
            return NutrientType(rawValue: rawID)
        }
        return nil
    }
}

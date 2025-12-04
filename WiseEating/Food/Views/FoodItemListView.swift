import SwiftUI
import SwiftData

struct FoodItemListView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    @State private var isShowingDeletePlanConfirmation = false
    @State private var planToDelete: MealPlan? = nil
    
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    private var headerTopPadding: CGFloat {
        return -safeAreaInsets.top + 10
    }
    
    // MARK: - Filter Enum (with "Plans")
    enum Filter: String, CaseIterable, Identifiable {
        case foods     = "Foods"
        case recipes   = "Recipes"
        case menus     = "Menus"
        case plans     = "Meal Plans"
        case favorites = "Favorites"
        case diets     = "Diets"
        case `default` = "Default"
        var id: String { rawValue }
    }
    
    // MARK: - Navigation State
    enum PresentedItem: Identifiable, Equatable {
        case newFood, newRecipe, newMenu, newDiet, newPlan
        case editFood(FoodItem), editRecipe(FoodItem), editMenu(FoodItem), editDiet(Diet), editPlan(MealPlan)
        case duplicateFood(FoodItemCopy), duplicateRecipe(FoodItemCopy), duplicateMenu(FoodItemCopy)
        case detail(FoodItem), detailDiet(Diet), detailPlan(MealPlan)
        
        var id: String {
            switch self {
            case .newFood: "newFood"
            case .newRecipe: "newRecipe"
            case .newMenu: "newMenu"
            case .newDiet: "newDiet"
            case .newPlan: "newPlan"
            case .editFood(let item): "editFood-\(item.id)"
            case .editRecipe(let item): "editRecipe-\(item.id)"
            case .editMenu(let item): "editMenu-\(item.id)"
            case .editDiet(let item): "editDiet-\(item.id)"
            case .editPlan(let item): "editPlan-\(item.id)"
            case .duplicateFood(let item): "duplicateFood-\(item.id)"
            case .duplicateRecipe(let item): "duplicateRecipe-\(item.id)"
            case .duplicateMenu(let item): "duplicateMenu-\(item.id)"
            case .detail(let item): "detail-\(item.id)"
            case .detailDiet(let item): "detailDiet-\(item.id)"
            case .detailPlan(let item): "detailPlan-\(item.id)"
            }
        }
        
        static func == (lhs: PresentedItem, rhs: PresentedItem) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @State private var presentedItem: PresentedItem? = nil
    @State private var isAddButtonVisible = true
    let profile: Profile?
    
    // MARK: - Search and Navigation Bindings
    @Binding var globalSearchText: String
    @Binding var isSearching: Bool
    @Binding var navBarIsHiden: Bool
    @Binding var isProfilesDrawerVisible: Bool
    @State private var SIsSearching = false
    @State private var SglobalSearchText = ""
    let onActivateSearch: () -> Void
    let onDismissSearch: () -> Void
    
    // MARK: - ViewModels and Data
    @Environment(\.modelContext) private var modelContext
    // --- START OF CHANGE ---
    @ObservedObject var vm: FoodListVM // Now passed from RootView
    // --- END OF CHANGE ---
    @StateObject var mealPlanVM: MealPlanListVM
    
    @Query(sort: \Diet.name) private var allDiets: [Diet]
    @State private var filteredDiets: [Diet] = []
    @State private var isShowingDeleteDietAlert = false
    @State private var dietToDelete: Diet?
    
    // MARK: - UI State
    @State private var buttonOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    private let buttonPositionKey = "foodItemFloatingButtonPosition"
    
    @State private var isShowingDeleteAllConfirmation = false
    @State private var isShowingDeleteItemConfirmation = false
    @State private var itemToDelete: FoodItem? = nil
    @State private var itemUsageCount: Int = 0
    
    @State private var editingDietProfilesFor: Diet? = nil
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @State private var stagingProfileIDs: Set<UUID> = []
    
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    
    // +++ НОВО: Състояние за непрочетени известия +++
    @State private var hasUnreadNotifications: Bool = false
    
    // MARK: - Initializer
    init(
        vm: FoodListVM, // <-- Added
        profile: Profile?,
        globalSearchText: Binding<String>,
        isSearching: Binding<Bool>,
        navBarIsHiden: Binding<Bool>,
        isProfilesDrawerVisible: Binding<Bool>,
        onActivateSearch: @escaping () -> Void,
        onDismissSearch: @escaping () -> Void,
        isSearchFieldFocused: FocusState<Bool>.Binding
    ) {
        self.vm = vm // <-- Added
        self.profile = profile
        self._globalSearchText = globalSearchText
        self._isSearching = isSearching
        self._navBarIsHiden = navBarIsHiden
        self._isProfilesDrawerVisible = isProfilesDrawerVisible
        self.onActivateSearch = onActivateSearch
        self.onDismissSearch = onDismissSearch
        self._isSearchFieldFocused = isSearchFieldFocused
        _mealPlanVM = StateObject(wrappedValue: MealPlanListVM(profile: profile))
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    mainContent
                        .opacity(presentedItem == nil ? 1 : 0)
                        .allowsHitTesting(presentedItem == nil)
                        .zIndex(0)
                    
                    if let item = presentedItem {
                        presentedItemView(for: item)
                            .transition(.move(edge: .trailing))
                            .zIndex(10)
                    }
                }
                
                if !isSearching && (vm.filter != .default && vm.filter != .favorites) && isAddButtonVisible && !navBarIsHiden {
                    addButton(geometry: geometry)
                }
            }
            .overlay {
                if editingDietProfilesFor != nil {
                    profileSelectionSheet
                }
            }
            .onReceive(timer) { _ in
                self.currentTimeString = Self.tFmt.string(from: Date())
            }
            .task { await checkForUnreadNotifications() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await checkForUnreadNotifications() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
                Task { await checkForUnreadNotifications() }
            }
        }
    }
    
    
    // +++ НОВА ПОМОЩНА ФУНКЦИЯ +++
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if let profile = profile {
                    userToolbar(for: profile)
                        .padding(.trailing, 50)
                        .padding(.leading, 40)
                        .padding(.horizontal, -20)
                        .padding(.bottom, 8)
                }
                
                UpdatePlanBanner()
                
                customToolbar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                let layoutMode: WrappingSegmentedControl<Filter>.LayoutMode =
                (horizontalSizeClass == .regular) ? .wrap : .scrollable
                
                WrappingSegmentedControl(selection: $vm.filter, layoutMode: layoutMode)
                    .padding(.bottom, 5)
                
                if vm.filter == .diets {
                    dietsManagementSection
                } else if vm.filter == .plans {
                    mealPlansSection
                } else if vm.items.isEmpty && !vm.isLoading {
                    Spacer()
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: "doc.text.magnifyingglass")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    } description: {
                        emptyStateDescription
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    Spacer()
                } else {
                    foodItemsList
                }
            }
            .padding(.top, headerTopPadding)
            
            if vm.isLoading && vm.items.isEmpty {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
                    }
                    .shadow(radius: 6)
                    .transition(.opacity)
            }
        }
        .alert("Delete Item", isPresented: $isShowingDeleteItemConfirmation) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    withAnimation {
                        if itemUsageCount > 0 {
                            // If the food is used in recipes – detach it first
                            vm.deleteDetachingFromRecipesAndMealPlans(item)
                        } else {
                            // Normal delete
                            vm.delete(item)
                        }
                    }
                }
                itemToDelete = nil
                itemUsageCount = 0
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
                itemUsageCount = 0
            }
        } message: {
            if let item = itemToDelete {
                if itemUsageCount > 0 {
                    Text("""
                This food item is used in \(itemUsageCount) recipes or menu or meal plans.
                If you delete it, it will be removed from those places.

                Are you sure you want to continue?
                """)
                } else {
                    Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
                }
            } else {
                Text("")
            }
        }
        .alert("Delete Diet", isPresented: $isShowingDeleteDietAlert) {
            Button("Delete", role: .destructive) {
                if let diet = dietToDelete {
                    deleteDiet(diet)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the \"\(dietToDelete?.name ?? "")\" diet? This cannot be undone.")
        }
        .alert("Delete Meal Plan", isPresented: $isShowingDeletePlanConfirmation) {
            Button("Delete Plan Only", role: .destructive) {
                if let plan = planToDelete {
                    mealPlanVM.delete(plan: plan, alsoDeleteMenus: false)
                }
                planToDelete = nil
            }
            
            Button("Delete Plan & Menus", role: .destructive) {
                if let plan = planToDelete {
                    mealPlanVM.delete(plan: plan, alsoDeleteMenus: true)
                }
                planToDelete = nil
            }
            
            Button("Cancel", role: .cancel) {
                planToDelete = nil
            }
        } message: {
            if let plan = planToDelete {
                // Ако имаш meals + linkedMenuID:
                let linkedMenuCount = plan.days
                    .flatMap { $0.meals }
                    .compactMap { $0.linkedMenuID }
                    .count
                
                if linkedMenuCount > 0 {
                    Text("""
        This meal plan has \(linkedMenuCount) linked menu(s).

        • "Delete Plan Only" will remove the plan but keep the menus wherever they are used.
        • "Delete Plan & Menus" will delete the plan and those linked menus as well.

        What would you like to do?
        """)
                } else {
                    Text("Are you sure you want to delete the meal plan '\(plan.name)'? This action cannot be undone.")
                }
            } else {
                Text("Are you sure you want to delete this meal plan?")
            }
        }

        .onAppear {
            vm.attach(context: modelContext)
            mealPlanVM.attach(context: modelContext)
            vm.searchText = globalSearchText
            vm.resetAndLoad()
            
            updateFilteredDiets()
            loadButtonPosition()
        }
        .onChange(of: globalSearchText) { _, newValue in
            vm.searchText = newValue
            if vm.filter == .diets {
                updateFilteredDiets()
            } else if vm.filter == .plans {
                mealPlanVM.searchText = newValue
            }
        }
        .onChange(of: vm.filter) { _, newFilter in
            if newFilter == .diets {
                updateFilteredDiets()
            } else if newFilter == .plans {
                mealPlanVM.fetchPlans()
            }
        }
        .onChange(of: allDiets) {
            updateFilteredDiets()
        }
        .onChange(of: modelContext) { _, new in
            vm.attach(context: new)
            mealPlanVM.attach(context: new)
        }
        .onReceive(NotificationCenter.default.publisher(for: .foodFavoriteToggled)) { _ in
            vm.pruneFavoritesAfterToggle()
        }
        .onChange(of: editingDietProfilesFor) { _, newDiet in
            guard let diet = newDiet else { return }
            let profilesWithDiet = profiles.filter { $0.diets.contains(where: { $0.id == diet.id }) }
            stagingProfileIDs = Set(profilesWithDiet.map { $0.id })
        }
    }
    
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear {
                    self.currentTimeString = Self.tFmt.string(from: Date())
                }
            
            Spacer()
            
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("openProfilesDrawer"), object: nil)
            }) {
                // +++ НАЧАЛО НА ПРОМЯНАТА: Обвиваме в ZStack +++
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter))
                                    .font(.headline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    
                    // +++ НОВО: Условна оранжева точка +++
                    if hasUnreadNotifications {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: 1, y: -1)
                    }
                }
                // +++ КРАЙ НА ПРОМЯНАТА +++
            }
            .buttonStyle(.plain)
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
    }
    
    private var customToolbar: some View {
        HStack {
            Group {
                if vm.filter == .default { Text("Default list").font(.title.bold()) }
                else if vm.filter == .foods { Text("Food list").font(.title.bold()) }
                else if vm.filter == .recipes { Text("Recipes list").font(.title.bold()) }
                else if vm.filter == .menus { Text("Menus list").font(.title.bold()) }
                else if vm.filter == .plans { Text("Meal Plans").font(.title.bold()) }
                else if vm.filter == .favorites { Text("Favorites").font(.title.bold()) }
                else if vm.filter == .diets { Text("Manage Diets").font(.title.bold()) }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func presentedItemView(for item: PresentedItem) -> some View {
        
        let onDismissItemFootView: (FoodItem?) -> Void = { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            vm.resetAndLoad()
        }
        
        let onDismissItemView: () -> Void = {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
        }
        
        let onDismissDietItemView: (Diet?) -> Void = {_ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
        }
        
        let onPlanEditorDismiss = {
            onDismissSearch()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            mealPlanVM.fetchPlans()
        }
        
        switch item {
        case .newFood:
            FoodItemEditorView(profile: profile, onDismiss: onDismissItemFootView)
        case .editFood(let food):
            FoodItemEditorView(food: food, profile: profile, onDismiss: onDismissItemFootView)
        case .duplicateFood(let foodCopy):
            FoodItemEditorView(dubFood: foodCopy, profile: profile, onDismiss: onDismissItemFootView)
            
        case .newRecipe:
            FoodItemReceptEditorView(profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
        case .editRecipe(let recipe):
            FoodItemReceptEditorView(food: recipe, profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
        case .duplicateRecipe(let recipeCopy):
            FoodItemReceptEditorView(dubFood: recipeCopy, profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
            
        case .newMenu:
            FoodItemMenuEditorView(profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
        case .editMenu(let menu):
            FoodItemMenuEditorView(food: menu, profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
        case .duplicateMenu(let menuCopy):
            FoodItemMenuEditorView(dubFood: menuCopy, profile: profile, globalSearchText: $globalSearchText, onDismiss: onDismissItemFootView, isSearchFieldFocused: $isSearchFieldFocused)
            
        case .detail(let food):
            FoodItemDetailView(food: food, profile: profile, onDismiss: onDismissItemView)
            
        case .newDiet:
            AddEditDietView(
                dietToEdit: nil,
                profile: profile,
                onDismiss: onDismissDietItemView,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                onDismissSearch: onDismissSearch
            )
        case .editDiet(let diet):
            AddEditDietView(
                dietToEdit: diet,
                profile: profile,
                onDismiss: onDismissDietItemView,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                onDismissSearch: onDismissSearch
            )
            
        case .detailDiet(let diet):
            DietDetailView(
                diet: diet,
                profile: self.profile,
                onDismiss: onDismissItemView,
                globalSearchText: $globalSearchText,
                onDismissSearch: onDismissSearch
            )
            
        case .newPlan:
            MealPlanEditorView(
                profile: profile!,
                navBarIsHiden: $navBarIsHiden,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: self.$isSearchFieldFocused,
                onDismiss: onPlanEditorDismiss
            )
        case .editPlan(let plan):
            MealPlanEditorView(
                profile: profile!,
                planToEdit: plan,
                navBarIsHiden: $navBarIsHiden,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: self.$isSearchFieldFocused,
                onDismiss: onPlanEditorDismiss
            )
        case .detailPlan(let plan):
            MealPlanDetailView(plan: plan, profile: self.profile!, onDismiss: onPlanEditorDismiss, navBarIsHiden: $navBarIsHiden)
        }
    }
    
    private var emptyStateTitle: String {
        if !vm.searchText.isEmpty { return "No Results for \"\(vm.searchText)\"" }
        switch vm.filter {
        case .foods: return "No Foods"
        case .recipes: return "No Recipes"
        case .menus: return "No Menus"
        case .plans: return "No Meal Plans"
        case .favorites: return "No Favorites"
        case .default: return "No Items Available"
        case .diets: return ""
        }
    }
    
    private var emptyStateDescription: Text {
        let text: String
        if !vm.searchText.isEmpty { text = "Try a different search term or change the filter." }
        else {
            switch vm.filter {
            case .foods: text = "Tap the '+' button to add your first food."
            case .recipes: text = "Tap the '+' button to add your first recipe."
            case .menus: text = "Tap the '+' button to add your first menu."
            case .plans: text = "Tap the '+' button to create your first meal plan."
            case .favorites: text = "You can add items to your favorites by swiping left on them."
            case .default: text = "Select a filter like 'Foods' or 'Recipes' to get started."
            case .diets: text = ""
            }
        }
        return Text(text)
    }
    
    private var foodItemsList: some View {
        List {
            ForEach(vm.items.filter { vm.filter != .favorites || $0.isFavorite }) { item in
                FoodRow(
                    item: item,
                    textColor: effectManager.currentGlobalAccentColor,
                    onItemTapped: {
                        present(item: .detail(item))
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActions(for: item)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            
            if vm.hasMore {
                ProgressView()
                    .onAppear { vm.loadNextPage() }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
            }
            
            Color.clear.frame(height: 150)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        .ignoresSafeArea(.all)
    }
    
    private var dietsManagementSection: some View {
        Group {
            if filteredDiets.isEmpty && !globalSearchText.isEmpty {
                ContentUnavailableView.search(text: globalSearchText)
            } else {
                List {
                    ForEach(filteredDiets) { diet in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diet.name)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                if diet.isDefault {
                                    Text("Default")
                                        .font(.caption2)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                                }
                            }
                            Spacer()
                            profileIconsPreview(for: diet)
                            Button(action: {
                                if isSearching {
                                    onDismissSearch()
                                }
                                withAnimation {
                                    editingDietProfilesFor = diet
                                    navBarIsHiden = true
                                    isProfilesDrawerVisible = false
                                }
                            }) {
                                Image(systemName: "person.2.fill")
                                    .font(.title3)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                    .padding(10)
                                    .glassCardStyle(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            present(item: .detailDiet(diet))
                        }
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                        .swipeActions(allowsFullSwipe: false) {
                            if !diet.isDefault {
                                Button(role: .destructive) {
                                    if #available(iOS 26.0, *) {
                                        deleteDiet(diet)
                                    } else {
                                        dietToDelete = diet
                                        isShowingDeleteDietAlert = true
                                    }
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                                }
                                .tint(.clear)
                            }
                            Button {
                                present(item: .editDiet(diet))
                            } label: {
                                Image(systemName: "pencil")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                            }
                            .tint(.clear)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    
                    Color.clear.frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
            }
        }
    }
    
    @ViewBuilder
    private var mealPlansSection: some View {
        if mealPlanVM.plans.isEmpty && globalSearchText.isEmpty {
            ContentUnavailableView("No Meal Plans", systemImage: "calendar.badge.plus", description: Text("Create your first meal plan by tapping the '+' button below."))
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        } else if mealPlanVM.plans.isEmpty {
            ContentUnavailableView.search(text: globalSearchText)
        } else {
            List {
                ForEach(mealPlanVM.plans) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        
                        HStack {
                            Text("\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")")
                            Text("•")
                            Text("Created: \(plan.creationDate.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        present(item: .detailPlan(plan))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button(role: .destructive) {
                            self.planToDelete = plan
                            self.isShowingDeletePlanConfirmation = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                        .tint(.clear)
                        
                        Button {
                            present(item: .editPlan(plan))
                        } label: {
                            Image(systemName: "pencil")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                        .tint(.clear)
                    }
                }
                Color.clear.frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        }
    }
    
    @ViewBuilder
    private func profileIconsPreview(for diet: Diet) -> some View {
        let associatedProfiles = profiles.filter { $0.diets.contains(where: { $0.id == diet.id }) }
        let displayProfiles = associatedProfiles.prefix(3)
        let remainingCount = max(associatedProfiles.count - displayProfiles.count, 0)
        HStack(spacing: -10) {
            ForEach(displayProfiles) { profile in
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .fill(effectManager.isLightRowTextColor ? .black : .white)
                                .stroke(effectManager.currentGlobalAccentColor, lineWidth: 1)
                        )
                    
                    
                    if let data = profile.photoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            Text(String(profile.name.first ?? "?"))
                                .font(.caption2).bold()
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                        .frame(width: 26, height: 26)
                    }
                }
            }
            if remainingCount > 0 {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .fill(effectManager.isLightRowTextColor ? .black : .white)
                                .stroke(effectManager.currentGlobalAccentColor, lineWidth: 0.5)
                        )
                    ZStack {
                        Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                        Text("+\(remainingCount)")
                            .font(.caption2).bold()
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 26, height: 26)
                }
            }
        }
    }
    
    @ViewBuilder
    private var profileSelectionSheet: some View {
        ZStack(alignment: .bottom) {
            
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingDietProfilesFor = nil
                            navBarIsHiden = false
                        }
                    }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            editingDietProfilesFor = nil
                            navBarIsHiden = false
                        }
                    }
            }
            
            
            VStack(spacing: 8) {
                ZStack {
                    HStack {
                        Text("Assign '\(editingDietProfilesFor?.name ?? "")' to Profiles")
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Spacer()
                        Button("Done") {
                            saveDietProfileAssignments()
                        }
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)
                    }
                }
                .padding(.horizontal).frame(height: 35)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(profiles) { profile in
                            Button {
                                if stagingProfileIDs.contains(profile.id) {
                                    stagingProfileIDs.remove(profile.id)
                                } else {
                                    stagingProfileIDs.insert(profile.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    if let data = profile.photoData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle")
                                            .font(.system(size: 40))
                                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(1))
                                    }
                                    
                                    Text(profile.name)
                                        .foregroundColor(effectManager.currentGlobalAccentColor)
                                    
                                    Spacer()
                                    
                                    if stagingProfileIDs.contains(profile.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(effectManager.currentGlobalAccentColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 150)
                }
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
    }
    
    private func updateFilteredDiets() {
        if globalSearchText.isEmpty {
            filteredDiets = allDiets
        } else {
            filteredDiets = allDiets.filter { $0.name.localizedCaseInsensitiveContains(globalSearchText) }
        }
    }
    
    private func deleteDiet(_ diet: Diet) {
        do {
            let allFoodItems = try modelContext.fetch(FetchDescriptor<FoodItem>())
            for item in allFoodItems {
                item.diets?.removeAll { $0.id == diet.id }
            }
            
            let allProfiles = try modelContext.fetch(FetchDescriptor<Profile>())
            for profile in allProfiles {
                profile.diets.removeAll { $0.id == diet.id }
            }
            
            modelContext.delete(diet)
            try modelContext.save()
        } catch {
            print("Failed to delete diet and update relationships: \(error)")
        }
    }
    
    @ViewBuilder
    private func swipeActions(for item: FoodItem) -> some View {
        Group {
            if item.isUserAdded {
                Button(role: .destructive) {
                    if #available(iOS 26.0, *) {
                        // На iOS 26 първо смятаме колко пъти се използва
                        let usage = vm.foodUsageCount(item)
                        if usage == 0 {
                            // Няма връзки → директно триене
                            withAnimation {
                                vm.delete(item)
                            }
                        } else {
                            // Има връзки → показваме алерта с детайли
                            self.itemToDelete = item
                            self.itemUsageCount = usage
                            self.isShowingDeleteItemConfirmation = true
                        }
                    } else {
                        // На по-стари iOS винаги минаваме през алерт
                        self.itemToDelete = item
                        self.itemUsageCount = vm.foodUsageCount(item)
                        self.isShowingDeleteItemConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .tint(.clear)
            }
            
            Button {
                if item.isMenu {
                    present(item: .duplicateMenu(FoodItemCopy(from: item)))
                } else if item.isRecipe {
                    present(item: .duplicateRecipe(FoodItemCopy(from: item)))
                } else {
                    present(item: .duplicateFood(FoodItemCopy(from: item)))
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .tint(.clear)
            
            if item.isUserAdded {
                Button {
                    if item.isMenu {
                        present(item: .editMenu(item))
                    } else if item.isRecipe {
                        present(item: .editRecipe(item))
                    } else {
                        present(item: .editFood(item))
                    }
                } label: {
                    Image(systemName: "pencil")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .tint(.clear)
            }
        }
    }
    
    private func dragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.isPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.isDragging = true
                }
            }
            .onEnded { value in
                self.isPressed = false
                if isDragging {
                    var newOffset = self.buttonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height
                    
                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top
                    let maxY = -25 + safeArea.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))
                    
                    self.buttonOffset = newOffset
                    self.saveButtonPosition()
                } else {
                    self.handleButtonTap()
                }
                self.isDragging = false
            }
    }
    
    private func bottomPadding(for geometry: GeometryProxy) -> CGFloat {
        guard geometry.size.width > 0 else { return 75 }
        let isTallScreen = (geometry.size.height / geometry.size.width) > 1.9
        return isTallScreen ? 75 : 95
    }
    
    private func trailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
    
    private func addButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(
            width: buttonOffset.width + gestureDragOffset.width,
            height: buttonOffset.height + gestureDragOffset.height
        )
        let scale = isDragging ? 1.15 : (isPressed ? 0.9 : 1.0)
        
        return ZStack {
            Image(systemName: "widget.large.badge.plus")
                .font(.title3)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: 60, height: 60)
        .glassCardStyle(cornerRadius: 32)
        .scaleEffect(scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .contentShape(Rectangle())
        .padding(.trailing, trailingPadding(for: geometry))
        .padding(.bottom, bottomPadding(for: geometry))
        .offset(currentOffset)
        .opacity(isAddButtonVisible ? 1 : 0)
        .disabled(!isAddButtonVisible)
        .gesture(dragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
    }
    
    private func present(item: PresentedItem) {
        if isSearching {
            SIsSearching = isSearching
            SglobalSearchText = globalSearchText
        }
        if isSearching {
            onDismissSearch()
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            presentedItem = item
            isAddButtonVisible = false
            
            let shouldHideNav: Bool
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            // Разширяваме логиката, за да включим всички случаи,
            // които трябва да скрият навигационната лента.
            switch item {
            case .newFood, .editFood, .duplicateFood, .detail, .detailDiet, .detailPlan:
                shouldHideNav = true
            default:
                // Всички останали случаи (като .newRecipe, .editDiet и т.н.)
                // ще оставят лентата видима по подразбиране.
                shouldHideNav = false
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
            
            navBarIsHiden = shouldHideNav
            isProfilesDrawerVisible = false
        }
    }
    
    private func handleButtonTap() {
        switch vm.filter {
        case .foods:
            present(item: .newFood)
        case .recipes:
            present(item: .newRecipe)
        case .menus:
            present(item: .newMenu)
        case .diets:
            present(item: .newDiet)
        case .plans:
            present(item: .newPlan)
        default:
            break
        }
    }
    
    private func saveButtonPosition() {
        let defaults = UserDefaults.standard
        defaults.set(buttonOffset.width, forKey: "\(buttonPositionKey)_width")
        defaults.set(buttonOffset.height, forKey: "\(buttonPositionKey)_height")
    }
    
    private func loadButtonPosition() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "\(buttonPositionKey)_width")
        let height = defaults.double(forKey: "\(buttonPositionKey)_height")
        self.buttonOffset = CGSize(width: width, height: height)
    }
    
    private func saveDietProfileAssignments() {
        guard let diet = editingDietProfilesFor else { return }
        
        for profile in profiles {
            let profileHasDiet = profile.diets.contains { $0.id == diet.id }
            let profileShouldHaveDiet = stagingProfileIDs.contains(profile.id)
            
            if profileShouldHaveDiet && !profileHasDiet {
                profile.diets.append(diet)
            } else if !profileShouldHaveDiet && profileHasDiet {
                profile.diets.removeAll { $0.id == diet.id }
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving diet-profile associations: \(error)")
        }
        
        withAnimation {
            editingDietProfilesFor = nil
            navBarIsHiden = false
        }
    }
    
    private struct FoodRow: View {
        let item: FoodItem
        let textColor: Color
        let onItemTapped: () -> Void
        
        var body: some View {
            FoodItemRowView(item: item)
                .foregroundColor(textColor)
                .contentShape(Rectangle())
                .onTapGesture { onItemTapped() }
        }
    }

}

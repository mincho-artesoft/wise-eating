import SwiftUI

struct LiquidTabBar: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Bindings от Parent View
    @Binding var menuState: MenuState
    @Binding var selectedTab: AppTab
    @Binding var isSearching: Bool
    @Binding var searchText: String
    @Binding var hasNewNutrition: Bool
    @Binding var hasNewTraining: Bool
    @Binding var hasUnreadAINotifications: Bool
    @Binding var navBarIsHiden: Bool
    @Binding var isSearchButtonVisible: Bool
    @Binding var isAIGenerating: Bool
   
    // Actions
    var onSearchTapped: () -> Void
    var onDismissSearchTapped: () -> Void
    @FocusState.Binding var isSearchFieldFocused: Bool

    // Animation Namespace
    @Namespace private var animation

    // Profile Menu Bindings
    @Binding var profilesMenuState: MenuState
    @Binding var isProfilesDrawerVisible: Bool
    
    // Local State
    @State private var localSearchText: String = ""
    @State private var isAnimatingSelection = false
    
    // --- НОВО: Следи върху кой таб е пръста по време на драг ---
    @State private var draggingTab: AppTab? = nil
    
    let standardTabs: [AppTab]

    init(
        menuState: Binding<MenuState>,
        selectedTab: Binding<AppTab>,
        isSearching: Binding<Bool>,
        searchText: Binding<String>,
        hasNewNutrition: Binding<Bool>,
        hasNewTraining: Binding<Bool>,
        hasUnreadAINotifications: Binding<Bool>,
        navBarIsHiden: Binding<Bool>,
        isAIGenerating: Binding<Bool>,
        isSearchButtonVisible: Binding<Bool>,
        tabs: [AppTab],
        onSearchTapped: @escaping () -> Void,
        onDismissSearchTapped: @escaping () -> Void,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        profilesMenuState: Binding<MenuState>,
        isProfilesDrawerVisible: Binding<Bool>
    ) {
        self._menuState = menuState
        self._selectedTab = selectedTab
        self._isSearching = isSearching
        self._searchText = searchText
        self._hasNewNutrition = hasNewNutrition
        self._hasNewTraining = hasNewTraining
        self._hasUnreadAINotifications = hasUnreadAINotifications
        self._navBarIsHiden = navBarIsHiden
        self._isAIGenerating = isAIGenerating
        self._isSearchButtonVisible = isSearchButtonVisible
        self.standardTabs = tabs
        self.onSearchTapped = onSearchTapped
        self.onDismissSearchTapped = onDismissSearchTapped
        self._isSearchFieldFocused = isSearchFieldFocused
        self._profilesMenuState = profilesMenuState
        self._isProfilesDrawerVisible = isProfilesDrawerVisible
    }

    // Помощна анимация за иконките
    private func triggerSelectionPop() {
        isAnimatingSelection = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.35).delay(0.15)) {
            isAnimatingSelection = false
        }
    }
    
    // Помощна функция за намиране на таб спрямо позицията на пръста
    private func getTab(at location: CGPoint, totalWidth: CGFloat) -> AppTab? {
        guard totalWidth > 0, !standardTabs.isEmpty else { return nil }
        let tabWidth = totalWidth / CGFloat(standardTabs.count)
        let index = Int(location.x / tabWidth)
        
        if index >= 0 && index < standardTabs.count {
            return standardTabs[index]
        }
        return nil
    }

    var body: some View {
        ZStack {
            let isTabVisible = standardTabs.contains(selectedTab)
            
            // --- 1. ПЛЪЗГАЩОТО СЕ БАЛОНЧЕ (BACKGROUND) ---
            if !isSearching && isTabVisible {
                Capsule()
                    .fill(effectManager.currentGlobalAccentColor.opacity(0.4))
                    .glassCardStyle(cornerRadius: 25)
                    .padding(.horizontal, 5)
                    // Визуално показваме draggingTab ако има такъв, иначе selectedTab
                    .matchedGeometryEffect(id: draggingTab ?? selectedTab, in: animation, isSource: false)
                    .frame(height: 44)
                    // Бърза анимация, за да следва пръста плътно
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: draggingTab)
                    .transition(.opacity)
            }
            
            // --- 2. СЪДЪРЖАНИЕТО ---
            HStack(spacing: 0) {
                
                // --- A. ТАБОВЕ ---
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(standardTabs) { tab in
                            TabItem(
                                tab: tab,
                                selectedTab: $selectedTab,
                                hasNewNutrition: $hasNewNutrition,
                                hasNewTraining: $hasNewTraining,
                                hasUnreadAINotifications: $hasUnreadAINotifications,
                                isAIGenerating: isAIGenerating,
                                accentColor: effectManager.currentGlobalAccentColor,
                                isAccentColorLight: effectManager.isLightRowTextColor,
                                animationNamespace: animation,
                                isAnimating: isAnimatingSelection
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .contentShape(Rectangle()) // Прави цялата зона активна за жестове
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // 1. Намираме кой таб е под пръста
                                guard let currentTab = getTab(at: value.location, totalWidth: geo.size.width) else { return }
                                
                                // 2. Обновяваме визуалната позиция на балона (draggingTab)
                                if draggingTab != currentTab {
                                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                                        draggingTab = currentTab
                                    }
                                    // Лека вибрация при преминаване през таб
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                                
                                // 3. Логика за TAP: Ако движението е минимално, сменяме веднага
                                if abs(value.translation.width) < 10 {
                                    if selectedTab != currentTab {
                                        selectedTab = currentTab
                                        triggerSelectionPop()
                                    }
                                }
                            }
                            .onEnded { value in
                                // 4. Логика за КРАЙ НА DRAG: Потвърждаваме избора
                                if let finalTab = getTab(at: value.location, totalWidth: geo.size.width) {
                                    if selectedTab != finalTab {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedTab = finalTab
                                        }
                                        triggerSelectionPop()
                                        
                                        // Скриване на UI елементи
                                        menuState = .collapsed
                                        navBarIsHiden = false
                                        profilesMenuState = .collapsed
                                        isProfilesDrawerVisible = false
                                    }
                                }
                                
                                // 5. Нулираме draggingTab
                                draggingTab = nil
                            }
                    )
                }
                .frame(height: 44)
                // Скриваме табовете при търсене
                .frame(maxWidth: isSearching ? 0 : .infinity)
                .opacity(isSearching ? 0 : 1)
                // Layout Priority: Табовете взимат всичкото налично място, оставено от бутона
                .layoutPriority(1)

                
                // --- B. ПОЛЕ ЗА ТЪРСЕНЕ (SEARCH FIELD) ---
                if isSearching {
                   ZStack(alignment: .leading) {
                       if localSearchText.isEmpty {
                           Text("Search...")
                               .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                               .padding(.leading, 4)
                       }
                       
                       TextField("", text: $localSearchText)
                           .foregroundColor(effectManager.currentGlobalAccentColor)
                           .tint(effectManager.currentGlobalAccentColor)
                           .disableAutocorrection(true)
                           .autocapitalization(.none)
                           .onChange(of: localSearchText) { _, newValue in
                               searchText = newValue
                           }
                   }
                   .padding(.leading, 20)
                   .focused($isSearchFieldFocused)
                   .transition(.opacity.animation(.easeIn(duration: 0.2).delay(0.1)))
                }
                
                // --- C. БУТОН ЗА ТЪРСЕНЕ ---
                if isSearchButtonVisible && !navBarIsHiden {
                    ZStack {
                        // Котва за анимацията
                        if !isSearching {
                             Color.clear
                                .frame(height: 44)
                                .matchedGeometryEffect(id: AppTab.search, in: animation, isSource: true)
                        }
                        
                        if isSearching {
                            Image("xmark_icon")
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        } else {
                            Image("search_icon")
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                        }
                    }
                    // Фиксирана ширина, за да не "бута" табовете
                    .frame(width: 50, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSearching { onDismissSearchTapped() } else { onSearchTapped() }
                    }
                    .transition(.scale(scale: 0.1).combined(with: .opacity))
                }
            }
        }
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(effectManager.isLightRowTextColor ? .white.opacity(0.2) : .black.opacity(0.2))
        }
        .glassCardStyle(cornerRadius: 50)
        .padding(.horizontal)
        .padding(.bottom, 8)
        // Анимации за UI промените
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: isSearching)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: isSearchButtonVisible)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: navBarIsHiden)
        .onAppear { localSearchText = searchText }
        .onChange(of: searchText) { _, newValue in
            if newValue != localSearchText { localSearchText = newValue }
        }
        .onChange(of: selectedTab) { _, _ in
            triggerSelectionPop()
        }
    }
}

// --- TabItem Component ---
private struct TabItem: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab
    @Binding var hasNewNutrition: Bool
    @Binding var hasNewTraining: Bool
    @Binding var hasUnreadAINotifications: Bool
    
    let isAIGenerating: Bool
    
    let accentColor: Color
    let isAccentColorLight: Bool
    let animationNamespace: Namespace.ID
    let isAnimating: Bool
    
    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                iconView
                
                // Notification Dots
                if hasNewNutrition && tab == .nutrition && selectedTab != .nutrition {
                    Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 1, y: 5)
                }
                if hasNewTraining && tab == .training && selectedTab != .training {
                    Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 1, y: 5)
                }
                if hasUnreadAINotifications && tab == .aiGenerate && selectedTab != .aiGenerate {
                    Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 1, y: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            Color.clear
                .matchedGeometryEffect(id: tab, in: animationNamespace, isSource: true)
        )
        // Мащабиране само при селекция и анимация
        .scaleEffect(selectedTab == tab && isAnimating ? 1.2 : 1.0)
    }
    
    @ViewBuilder
    private var iconView: some View {
        if tab == .aiGenerate {
            BreathingAssetIcon(imageName: tab.iconName, isActive: isAIGenerating)
                .frame(height: 44)
        } else {
            Image(tab.iconName)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .frame(height: 44)
        }
    }
}

// --- Breathing Icon for AI ---
private struct BreathingAssetIcon: View {
    let imageName: String
    let isActive: Bool

    @State private var breathingScale: CGFloat = 1.0
    @State private var breathingOpacity: Double = 1.0
    @State private var isAnimating = false

    var body: some View {
        Image(imageName)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
            .scaleEffect(breathingScale)
            .opacity(breathingOpacity)
            .onAppear {
                if isActive { startBreathing() }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue { startBreathing() } else { stopBreathing() }
            }
    }

    private func startBreathing() {
        guard !isAnimating else { return }
        isAnimating = true
        breathingScale = 1.0
        breathingOpacity = 1.0

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            breathingScale = 1.08
            breathingOpacity = 0.65
        }
    }

    private func stopBreathing() {
        isAnimating = false
        withAnimation(.easeOut(duration: 0.2)) {
            breathingScale = 1.0
            breathingOpacity = 1.0
        }
    }
}

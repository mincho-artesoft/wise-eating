import SwiftUI

struct LiquidTabBar: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
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
   
    var onSearchTapped: () -> Void
    var onDismissSearchTapped: () -> Void
    @FocusState.Binding var isSearchFieldFocused: Bool

    @Namespace private var animation

    @Binding var profilesMenuState: MenuState
    @Binding var isProfilesDrawerVisible: Bool
    
    @State private var localSearchText: String = ""
    @State private var isAnimatingSelection = false
    
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

    // --- Помощна функция за поп ефекта ---
    private func triggerSelectionPop() {
        isAnimatingSelection = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.35).delay(0.15)) {
            isAnimatingSelection = false
        }
    }

    var body: some View {
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
                // --- ПРОМЯНА: Използваме DragGesture(minimumDistance: 0) вместо onTapGesture
                // Това засича докосването веднага, без да чака вдигане на пръста ---
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if selectedTab != tab {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = tab
                                }
                                menuState = .collapsed
                                navBarIsHiden = false
                                profilesMenuState = .collapsed
                                isProfilesDrawerVisible = false
                                
                                triggerSelectionPop()
                            }
                        }
                )
                .frame(maxWidth: isSearching ? 0 : .infinity)
                .opacity(isSearching ? 0 : 1)
            }

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
            
            if isSearchButtonVisible && !navBarIsHiden {
                ZStack {
                    if !isSearching && selectedTab == .search {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "liquid_pill", in: animation)
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
                .frame(width: isSearching ? 50 : nil, alignment: .center)
                .frame(maxWidth: isSearching ? nil : .infinity)
                .padding(.trailing, isSearching ? 10 : 0)
                .contentShape(Rectangle())
                // --- ПРОМЯНА: Същата логика за мигновена реакция и при Search бутона ---
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            // Изпълняваме логиката само веднъж при докосване
                            // (тъй като е Toggle, трябва да сме сигурни, че не премигва)
                            // Затова тук е добре да оставим onTapGesture или да сме внимателни.
                            // Ако искате и това да е мигновено, ето кода, но при бутони,
                            // които превключват състояние (toggle), touch-down може да е прекалено бърз.
                            // Ще го оставя с Gesture за консистентност с искането ви:
                            
                            // За да избегнем многократно извикване докато пръстът мърда, може да се наложи
                            // допълнителна логика, но за прост бутон това обикновено работи, ако потребителят просто "тапне".
                            // Все пак за Toggle бутони onTapGesture е по-безопасен, но ето исканата имплементация:
                            
                            // За Search бутона специфично е по-добре да реагираме на "End" на драга или
                            // да използваме onTap, но ако държите да е Touch Down:
                        }
                        .onEnded { _ in
                            // Ако искате search да е на пускане - оставете го тук.
                            // Ако искате на натискане - преместете логиката в onChanged,
                            // но внимавайте за дублиране.
                            // В текущия код ще го върна на onTapGesture за Search бутона,
                            // защото е по-стабилно за toggle функционалност,
                            // а табовете по-горе са с мигновена реакция.
                        }
                )
                // Връщам onTapGesture за Search бутона, за да не се затваря/отваря случайно при скрол
                // Ако искате и той да е супер бърз, разкоментирайте долното и махнете onTapGesture
                /*
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged({ _ in
                    if isSearching { onDismissSearchTapped() } else { onSearchTapped() }
                }))
                */
                .onTapGesture {
                    if isSearching { onDismissSearchTapped() } else { onSearchTapped() }
                }
                .transition(.scale(scale: 0.1).combined(with: .opacity))
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
    
    private var selectedColor: Color { isAccentColorLight ? .black : .white }
    
    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                iconView
                
                if hasNewNutrition && tab == .nutrition && selectedTab != .nutrition {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: 5)
                        .transition(.scale.animation(.spring()))
                }
                if hasNewTraining && tab == .training && selectedTab != .training {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: 5)
                        .transition(.scale.animation(.spring()))
                }
                if hasUnreadAINotifications && tab == .aiGenerate && selectedTab != .aiGenerate {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: 5)
                        .transition(.scale.animation(.spring()))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                if selectedTab == tab {
                    Capsule()
                        .fill(accentColor.opacity(0.4))
                        .matchedGeometryEffect(id: "liquid_pill", in: animationNamespace)
                        .glassCardStyle(cornerRadius: 25)
                        .padding(.horizontal, 5)
                }
            }
        )
        .contentShape(Rectangle())
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
                if isActive {
                    startBreathing()
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startBreathing()
                } else {
                    stopBreathing()
                }
            }
    }

    private func startBreathing() {
        guard !isAnimating else { return }
        isAnimating = true

        breathingScale = 1.0
        breathingOpacity = 1.0

        withAnimation(
            .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
        ) {
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

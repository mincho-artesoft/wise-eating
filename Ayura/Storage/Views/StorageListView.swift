import SwiftUI
import SwiftData

struct StorageListView: View {
    @FocusState.Binding var isSearchFieldFocused: Bool   // 👈 НОВО

    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var navBarIsHiden: Bool
    let profile: Profile
    @Binding var globalSearchText: String
    @Binding var isSearching: Bool

    // --- НАЧАЛО НА ПРОМЯНА 1: Добавяме safeAreaInsets и състояния за часовника ---
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    // --- КРАЙ НА ПРОМЯНА 1 ---

    let onShouldActivateGlobalSearch: () -> Void
    let onShouldDismissGlobalSearch: () -> Void
    @State private var SIsSearching = false
    @State private var SglobalSearchText = ""
    @StateObject private var viewModel: StorageListVM

    @State private var isShowingDeleteAllConfirmation = false
    @State private var selectedItemForMenu: StorageItem?
    @State private var detailMenuState: MenuState = .collapsed
    
    @State private var isShowingDeleteItemConfirmation = false
    @State private var itemToDelete: StorageItem? = nil
    
    @State private var showStorageEditor = false
    
    // +++ НОВО: Състояние за непрочетени известия +++
    @State private var hasUnreadNotifications: Bool = false
    
    @State private var isAddButtonVisible: Bool = true
    @State private var buttonOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    private let buttonPositionKey = "floatingStorageButtonPosition"

    init(profile: Profile,
         globalSearchText: Binding<String>,
         onShouldActivateGlobalSearch: @escaping () -> Void,
         onShouldDismissGlobalSearch: @escaping () -> Void,
         navBarIsHiden: Binding<Bool>,
         isSearching: Binding<Bool>,
         isSearchFieldFocused: FocusState<Bool>.Binding) {   // 👈 НОВО
        self.profile = profile
        self._globalSearchText = globalSearchText
        self.onShouldActivateGlobalSearch = onShouldActivateGlobalSearch
        self.onShouldDismissGlobalSearch = onShouldDismissGlobalSearch
        _viewModel = StateObject(wrappedValue: StorageListVM(profile: profile))
        self._navBarIsHiden = navBarIsHiden
        self._isSearching = isSearching
        self._isSearchFieldFocused = isSearchFieldFocused   // 👈 НОВО
    }


    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    NavigationStack {
                        listViewContent
                    }

                    if showStorageEditor {
                        StorageEditorView(
                            owner: profile,
                            globalSearchText: $globalSearchText,
                            onDismiss: { shouldDismissGlobalSearch in
                                if shouldDismissGlobalSearch {
                                    self.onShouldDismissGlobalSearch()
                                }
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showStorageEditor = false
                                    isAddButtonVisible = true
                                    if SIsSearching {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            onShouldActivateGlobalSearch()
                                            globalSearchText = SglobalSearchText
                                            SIsSearching = false
                                        }
                                    }
                                }
                                viewModel.reloadData()
                            },
                            onShouldDismissGlobalSearch : onShouldDismissGlobalSearch,
                            onShouldActivateGlobalSearch:  onShouldActivateGlobalSearch,
                            isSearching: $isSearching,
                            isSearchFieldFocused: $isSearchFieldFocused      // 👈 НОВО
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing),
                                                removal: .move(edge: .trailing)))
                        .zIndex(10)
                    }

                }
                
                if !isSearching{
                    addButton(geometry: geometry)
                }
            }
           
        }
        // --- НАЧАЛО НА ПРОМЯНА 3: Добавяме onReceive за таймера ---
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        // --- КРАЙ НА ПРОМЯНА 3 ---
        .onChange(of: globalSearchText) { _, newValue in
            viewModel.searchText = newValue
        }
        .onChange(of: detailMenuState) { _, newValue in
            if newValue == .collapsed {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedItemForMenu = nil
                    navBarIsHiden = false
                    print("SIsSearching1A",SIsSearching)
                    if SIsSearching{
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onShouldActivateGlobalSearch()
                            globalSearchText = SglobalSearchText
                            SIsSearching = false
                            print("SIsSearching2A",SIsSearching)
                        }
                    }
                }
                viewModel.reloadData()
            }
        }
        .onAppear {
            viewModel.searchText = globalSearchText
            viewModel.reloadData()
            viewModel.triggerConsolidationIfNeeded()
        }
        // +++ НОВО: Добавяме .task и .onReceive за проверка на известия +++
        .task {
            await checkForUnreadNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await checkForUnreadNotifications()
            }
        }
        // --- START OF CHANGE: Add observer for notification status changes ---
        .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
            Task {
                await checkForUnreadNotifications()
            }
        }
        // --- END OF CHANGE ---
        .overlay {
            if let item = selectedItemForMenu {
                ZStack {
                    
                    if effectManager.isLightRowTextColor {
                        Color.black.opacity(0.4).ignoresSafeArea()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    detailMenuState = .collapsed
                                }
                            }
                    } else {
                        Color.white.opacity(0.4).ignoresSafeArea()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    detailMenuState = .collapsed
                                }
                            }
                    }
                    
                    DraggableMenuView(
                        menuState: $detailMenuState,
                        customTopGap:  UIScreen.main.bounds.height * 0.1,
                        horizontalContent: { EmptyView() },
                        verticalContent: {
                            StorageItemDetailView(item: item, viewModel: viewModel, detailMenuState: $detailMenuState)
                                .padding(.bottom, -40)
                        },
                        onStateChange: { newState in
                            if newState == .collapsed {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedItemForMenu = nil
                                    navBarIsHiden = false
                                }
                                
                             
                                viewModel.reloadData()
                            }
                        }
                    )
                    .edgesIgnoringSafeArea(.all)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedItemForMenu)
            }
        }
        .alert("Delete Item", isPresented: $isShowingDeleteItemConfirmation) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    withAnimation {
                        viewModel.deleteStorageItem(with: item.id)
                    }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete '\(itemToDelete?.food?.name ?? "this item")' from your storage? This action cannot be undone.")
        }
    }
    
    // +++ НОВА ПОМОЩНА ФУНКЦИЯ +++
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    // MARK: - Updated Floating Button Logic
        
        private func bottomPadding(for geometry: GeometryProxy) -> CGFloat {
            let size = geometry.size
            guard size.width > 0 else { return 75 }
            let aspectRatio = size.height / size.width
            return aspectRatio > 1.9 ? 75 : 95
        }
        
        private func trailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
        
        private func dragGesture(geometry: GeometryProxy) -> some Gesture {
            let buttonSize: CGFloat = 60
            let radius = buttonSize / 2
            
            return DragGesture(minimumDistance: 0)
                .updating($gestureDragOffset) { value, state, _ in
                    // Жив превод по време на drag – без анимация
                    state = value.translation
                }
                .onChanged { value in
                    let distance = max(abs(value.translation.width), abs(value.translation.height))
                    
                    if distance > 6 {
                        // Вече влачим – махаме "pressed" и маркираме "dragging"
                        if !isDragging {
                            isDragging = true
                            isPressed = false
                        }
                    } else {
                        // Малко мърдане = натиснат бутон
                        isPressed = true
                    }
                }
                .onEnded { value in
                    let safeArea = geometry.safeAreaInsets
                    let size = geometry.size
                    
                    // Базова позиция (дясно-долу) спрямо размера + паддингите
                    let baseX = size.width  - trailingPadding(for: geometry) - radius
                    let baseY = size.height - bottomPadding(for: geometry)   - radius
                    
                    // Центърът, ако приложим текущия offset + преместеното
                    let rawCenterX = baseX + buttonOffset.width  + value.translation.width
                    let rawCenterY = baseY + buttonOffset.height + value.translation.height
                    
                    // Ограничаваме центъра ВЪТРЕ в екрана
                    let minX = radius
                    let maxX = size.width  - radius
                    let minY = radius + safeArea.top
                    let maxY = size.height - radius - safeArea.bottom
                    
                    let clampedCenterX = min(max(rawCenterX, minX), maxX)
                    let clampedCenterY = min(max(rawCenterY, minY), maxY)
                    
                    // Новият offset е просто разлика спрямо базовата позиция
                    let newOffset = CGSize(
                        width:  clampedCenterX - baseX,
                        height: clampedCenterY - baseY
                    )
                    
                    if isDragging {
                        buttonOffset = newOffset
                        saveButtonPosition()
                    } else {
                        // Тап (без реален drag)
                        handleButtonTap()
                    }
                    
                    isDragging = false
                    isPressed = false
                }
        }
        
        private func addButton(geometry: GeometryProxy) -> some View {
            let buttonSize: CGFloat = 60
            let radius = buttonSize / 2
            let safeArea = geometry.safeAreaInsets
            let size = geometry.size
            
            // Базова позиция (дясно-долу)
            let baseX = size.width  - trailingPadding(for: geometry) - radius
            let baseY = size.height - bottomPadding(for: geometry)   - radius
            
            // Център със запазения offset + текущия drag
            let rawCenterX = baseX + buttonOffset.width  + gestureDragOffset.width
            let rawCenterY = baseY + buttonOffset.height + gestureDragOffset.height
            
            // Ограничаваме центъра ВЪТРЕ в екрана (и safe area)
            let minX = radius
            let maxX = size.width  - radius
            let minY = radius + safeArea.top
            let maxY = size.height - radius - safeArea.bottom
            
            let centerX = min(max(rawCenterX, minX), maxX)
            let centerY = min(max(rawCenterY, minY), maxY)
            
            let scale = isDragging ? 1.05 : (isPressed ? 0.92 : 1.0)
            
            return ZStack {
                Image(systemName: "widget.large.badge.plus")
                    .font(.title3)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .frame(width: buttonSize, height: buttonSize)
            .glassCardStyle(cornerRadius: radius)
            .scaleEffect(scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
            .contentShape(Circle())
            .position(x: centerX, y: centerY) // Използваме position вместо offset
            .opacity(isAddButtonVisible ? 1 : 0)
            .disabled(!isAddButtonVisible)
            .gesture(dragGesture(geometry: geometry))
            .transition(.scale.combined(with: .opacity))
        }
    
    private func handleButtonTap() {
        presentStorageEditor()
    }
    
    private func presentStorageEditor() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAddButtonVisible = false
            showStorageEditor = true
        }
        
        if isSearching {
            SIsSearching = isSearching
            SglobalSearchText = globalSearchText
            onShouldDismissGlobalSearch()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onShouldActivateGlobalSearch()
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

    // --- НАЧАЛО НА ПРОМЯНА 5: Добавяме userToolbar ViewBuilder ---
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
    // --- КРАЙ НА ПРОМЯНА 5 ---

    private var customToolbar: some View {
        HStack {
            Text("Storage")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            Spacer()
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    @ViewBuilder
    private var listViewContent: some View {
        // --- НАЧАЛО НА ПРОМЯНА 6: Обвиваме всичко във VStack и прилагаме padding-а ---
        VStack(spacing: 0) {
            userToolbar(for: profile)
                .padding(.trailing, 50)
                .padding(.leading, 40)
                .padding(.horizontal, -20)
                .padding(.bottom, 8)

            UpdatePlanBanner()
            
            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                
                Group {
                    if viewModel.filteredItems.isEmpty && globalSearchText.isEmpty {
                        ContentUnavailableView {
                            Label("No Items in Storage", systemImage: "archivebox")
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        } description: {
                            Text("Tap the '+' button to add your first item.")
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                    } else if viewModel.filteredItems.isEmpty && !globalSearchText.isEmpty {
                         ContentUnavailableView.search(text: globalSearchText)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    } else {
                        List {
                            let items = viewModel.filteredItems
                            
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if let food = item.food {
                                    let isExpired = item.firstExpirationDate.map {
                                        Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: Date())
                                    } ?? false
                                    
                                    // 👉 Рекламен ред преди елемента, според индекса
                                    if shouldShowAd(at: index) {
                                        AdRowView() // 👈 използваме твоя AdRowView
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                                            .padding(.bottom, 4)
                                        
                                    }

                                    FoodItemRowStorageView(
                                        item: food,
                                        amount: item.totalQuantity
                                    )
                                    .overlay {
                                        if isExpired {
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(.orange, lineWidth: 3)
                                        }
                                    }
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedItemForMenu = item
                                            detailMenuState = .full
                                            navBarIsHiden = true
                                            if isSearching {
                                                print("SIsSearching1", SIsSearching)
                                                SIsSearching = isSearching
                                                print("SIsSearching2", SIsSearching)
                                                SglobalSearchText = globalSearchText
                                                onShouldDismissGlobalSearch()
                                            }
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            if #available(iOS 26.0, *) {
                                                withAnimation {
                                                    viewModel.deleteStorageItem(with: item.id)
                                                }
                                            } else {
                                                self.itemToDelete = item
                                                self.isShowingDeleteItemConfirmation = true
                                            }
                                        } label: {
                                            Image(systemName: "trash.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                        }
                                        .tint(.clear)
                                    }
                                }
                            }
                            
                            Color.clear
                                .frame(height: 150)
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
        }
        .padding(.top, headerTopPadding)
        // --- КРАЙ НА ПРОМЯНАТА 6 ---
        .onAppear(perform: loadButtonPosition)
        .navigationBarHidden(true)
    }
    
    private func shouldShowAd(at index: Int) -> Bool {
        // 👑 Premium / платен план – не показваме реклами
        if !AdsConfiguration.shouldShowAds {
            return false
        }
        
        // Пропускаме първите 2 реда, за да не е реклама най-отгоре
        if index < 2 { return false }
        
        // Същият ритъм както в TrainingView / NodesListView:
        // цикъл от 7 – реклами на остатък 2 и 5
        // Индекси: 2, 5, 9, 12, 16, 19, ...
        let remainder = index % 7
        if remainder == 2 || remainder == 5 {
            return true
        }
        
        return false
    }

}

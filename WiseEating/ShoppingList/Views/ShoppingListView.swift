// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/ShoppingList/Views/ShoppingListView.swift

import SwiftUI
import SwiftData
import EventKit
import Combine

struct ShoppingListView: View {
    @Binding var navBarIsHiden: Bool
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @FocusState.Binding var isSearchFieldFocused: Bool

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime

    let profile: Profile
    @Binding var globalSearchText: String

    @StateObject private var viewModel: ShoppingListViewModel
    @State private var listToPresent: ShoppingListModel?
    
    @StateObject private var coordinator = NavigationCoordinator.shared
    @State private var navigationCancellable: AnyCancellable?

    // MARK: - Calendar State
    @State private var isShowingCalendarView = false
    @State private var calendarDate = Date()
    @State private var calendarEvents: [EventDescriptor] = []
    @State private var calendarCoordinator: ShoppingTwoWayPinnedSingleDayMultiCalendarWrapper.Coordinator?

    // MARK: - Other State
    @State private var isShowingAnalyticsView = false
    @State private var isShowingDeleteAllConfirmation = false
    @State private var hasPresentedStartupList = false
    @Binding var isSearching: Bool
    
    @State private var isShowingDeleteListConfirmation = false
    @State private var listToDelete: ShoppingListModel? = nil
    
    // +++ НОВО: Състояние за непрочетени известия +++
    @State private var hasUnreadNotifications: Bool = false
    
    let onShouldActivateGlobalSearch: () -> Void
    let onShouldDismissGlobalSearch: () -> Void
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/3): Добавяме closures ---
    let onHideSearchButton: () -> Void
    let onShowSearchButton: () -> Void
    // --- КРАЙ НА ПРОМЯНАТА (1/3) ---

    @State private var buttonOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    
    @State private var isAddButtonVisible: Bool = true
    
    private let buttonPositionKey = "floatingShoppingButtonPosition"
    
    // --- НАЧАЛО НА ПРОМЯНАТА (2/3): Обновяваме init ---
    init(profile: Profile,
           globalSearchText: Binding<String>,
           onShouldActivateGlobalSearch: @escaping () -> Void,
           onShouldDismissGlobalSearch: @escaping () -> Void,
           isSearching: Binding<Bool>,
           isSearchFieldFocused: FocusState<Bool>.Binding,
           onHideSearchButton: @escaping () -> Void,
           onShowSearchButton: @escaping () -> Void,
           navBarIsHiden: Binding<Bool> // <-- ДОБАВЕТЕ ТОЗИ ПАРАМЕТЪР
      ) {
          self.profile = profile
          self._globalSearchText = globalSearchText
          _viewModel = StateObject(wrappedValue: ShoppingListViewModel(profile: profile))
          self.onShouldActivateGlobalSearch = onShouldActivateGlobalSearch
          self.onShouldDismissGlobalSearch = onShouldDismissGlobalSearch
          self._isSearching = isSearching
          self._isSearchFieldFocused = isSearchFieldFocused
          self.onHideSearchButton = onHideSearchButton
          self.onShowSearchButton = onShowSearchButton
          self._navBarIsHiden = navBarIsHiden // <-- ДОБАВЕТЕ ТОЗИ РЕД
      }
    // --- КРАЙ НА ПРОМЯНАТА (2/3) ---

    private var filteredLists: [ShoppingListModel] {
            if globalSearchText.isEmpty {
                return viewModel.lists
            } else {
                return viewModel.lists.filter { list in
                    list.items.contains { item in
                        item.name.localizedCaseInsensitiveContains(globalSearchText)
                    }
                }
            }
        }

    private var headerTopPadding: CGFloat {
        return -safeAreaInsets.top + 10
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                mainView
                
                if !isSearching && !isShowingCalendarView && listToPresent == nil && !isShowingAnalyticsView {
                    addButton(geometry: geometry)
                }
            }
            .onReceive(timer) { _ in
                self.currentTimeString = Self.tFmt.string(from: Date())
            }
            .onReceive(coordinator.$pendingShoppingListID) { pendingID in
                guard let listID = pendingID else { return }
                
                navigationCancellable = viewModel.$isDataLoaded
                    .filter { $0 == true }
                    .first()
                    .sink { _ in
                        let descriptor = FetchDescriptor<ShoppingListModel>(predicate: #Predicate { $0.id == listID })
                        if let list = try? modelContext.fetch(descriptor).first {
                            present(list: list)
                            coordinator.pendingShoppingListID = nil
                        } else {
                            print("ShoppingListView: Не е намерен списък с ID \(listID) от нотификация, дори след зареждане.")
                            coordinator.pendingShoppingListID = nil
                        }
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
                Task {
                    await checkForUnreadNotifications()
                }
            }
            .task {
                await checkForUnreadNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await checkForUnreadNotifications()
                }
            }
        }
    }
    
    // +++ НОВА ПОМОЩНА ФУНКЦИЯ +++
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    @ViewBuilder
    private var mainView: some View {
        ZStack {
            if isShowingCalendarView {
                calendarView
                    .zIndex(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isShowingAnalyticsView {
                ShoppingListAnalyticsView(
                    profile: profile,
                    onDismiss: {
                        withAnimation(.easeInOut) {
                            isShowingAnalyticsView = false
                            isAddButtonVisible = true
                        }
                    }
                )
                .zIndex(1)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else if let list = listToPresent {
                ShoppingListDetailView(
                    list: list,
                    viewModel: viewModel,
                    isNew: list.modelContext == nil,
                    globalSearchText: $globalSearchText,
                    isSearching: $isSearching,
                    onDismiss: dismissDetailView,
                    onDismissSearch: onShouldDismissGlobalSearch,
                    onShowCalendar: handleShowCalendarFromDetail,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    navBarIsHiden: $navBarIsHiden // <-- ПОДАЙТЕ BINDING-А ТУК
                )
                .zIndex(1)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
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
                        listViewContent
                    }
                }
                .padding(.top, headerTopPadding)
                .zIndex(0)
                .transition(.opacity)
                .onAppear {
                    viewModel.setup(context: modelContext)
                    let shouldAnimateStartup = listToPresent == nil
                    presentStartupListIfNeeded(animate: shouldAnimateStartup)
                    loadButtonPosition()
                }
            }
        }
    }

    // MARK: - Calendar View & Logic

    @ViewBuilder
    private var calendarView: some View {
        let wrapper = ShoppingTwoWayPinnedSingleDayMultiCalendarWrapper(
            fromDate: $calendarDate,
            events: $calendarEvents,
            profile: self.profile,
            eventStore: CalendarViewModel.shared.eventStore,
            onPresentShoppingList: { event in
                presentList(for: event)
            },
            onShowListsTap: {
                deactivateShoppingCalendarView()
            }
        )

        wrapper
            .onAppear {
                if self.calendarCoordinator == nil {
                    self.calendarCoordinator = wrapper.makeCoordinator()
                }
                self.calendarCoordinator?.reloadCurrentRange()
            }
            .onChange(of: calendarDate) {
                self.calendarCoordinator?.reloadCurrentRange()
            }
            .ignoresSafeArea()
    }
    
    private func presentList(for event: EKEvent) {
        guard let notes = event.notes,
              let jsonString = OptimizedInvisibleCoder.decode(from: notes),
              let jsonData = jsonString.data(using: .utf8) else {
            print("Cannot decode ShoppingList from this event.")
            return
        }
        
        do {
            let payload = try JSONDecoder().decode(ShoppingListPayload.self, from: jsonData)
            let listID = payload.id
            
            let descriptor = FetchDescriptor<ShoppingListModel>(predicate: #Predicate { $0.id == listID })
            if let list = try modelContext.fetch(descriptor).first {
                deactivateShoppingCalendarView()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.present(list: list)
                }
            } else {
                print("ShoppingListModel not found with ID: \(listID)")
            }
        } catch {
            print("Error decoding payload from event: \(error)")
        }
    }

    // --- НАЧАЛО НА ПРОМЯНАТА (3/3): Извикваме функциите тук ---
    private func activateShoppingCalendarView() {
        withAnimation(.easeInOut) {
            isShowingCalendarView = true
        }
        onHideSearchButton()
    }

    private func deactivateShoppingCalendarView() {
        withAnimation(.easeInOut) {
            isShowingCalendarView = false
        }
        onShowSearchButton()
    }
    // --- КРАЙ НА ПРОМЯНАТА (3/3) ---

    // MARK: - Main List View & Detail View

    private func handleShowCalendarFromDetail(date: Date) {
        self.calendarDate = date
        dismissDetailView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.activateShoppingCalendarView()
        }
    }

    private func dismissDetailView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            listToPresent = nil
            isAddButtonVisible = true
        }
        
        if isSearching {
            onShouldDismissGlobalSearch()
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
            Text("Shopping Lists").font(.title.bold()).foregroundColor(effectManager.currentGlobalAccentColor)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    self.calendarDate = Date()
                    activateShoppingCalendarView()
                } label: {
                    Image(systemName: "calendar").font(.title3).padding(8)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Divider().frame(height: 20).padding(.horizontal, 4)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                Button {
                    withAnimation {
                        isShowingAnalyticsView = true
                        isAddButtonVisible = false
                    }
                } label: {
                    Image(systemName: "chart.bar.xaxis").font(.title3).padding(8)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                
            }.glassCardStyle(cornerRadius: 20)
        }.foregroundColor(effectManager.currentGlobalAccentColor)
    }

    @ViewBuilder
    private var listViewContent: some View {
        Group {
            if viewModel.lists.isEmpty {
                ContentUnavailableView("No Shopping Lists", systemImage: "cart.badge.plus", description: Text("Create your first list by tapping the “+” button below.")).foregroundStyle(effectManager.currentGlobalAccentColor)
            } else if filteredLists.isEmpty && !globalSearchText.isEmpty {
                ContentUnavailableView.search(text: globalSearchText)
            } else {
                List {
                    ForEach(filteredLists) { list in
                        Button {
                            present(list: list)
                        } label: { row(for: list) }
                        .buttonStyle(.plain)
                        .glassCardStyle(cornerRadius: 20)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // --- НАЧАЛО НА ПРОМЯНАТА ---
                            Button(role: .destructive) {
                                // За iOS 26 и по-нови версии, изтриваме директно.
                                if #available(iOS 26.0, *) {
                                    withAnimation { viewModel.delete(list: list) }
                                } else {
                                    // За по-стари версии, показваме алерт за потвърждение.
                                    self.listToDelete = list
                                    self.isShowingDeleteListConfirmation = true
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                            }
                            .tint(.clear)
                            // --- КРАЙ НА ПРОМЯНАТА ---

                            Button {
                                let originalList = list
                                let copy = viewModel.duplicate(list: originalList)
                                present(list: copy)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                            }
                            .tint(.clear)
                        }
                    }
                    Color.clear.frame(height: 150).listRowBackground(Color.clear).listRowSeparator(.hidden)
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
        .onReceive(NotificationCenter.default.publisher(for: .shoppingListDidChange)) { _ in
            viewModel.fetchLists()
        }
        .onChange(of: viewModel.lists) {
            presentStartupListIfNeeded(animate: false)
        }
        .alert("Delete List", isPresented: $isShowingDeleteListConfirmation) {
            Button("Delete", role: .destructive) {
                if let list = listToDelete {
                    withAnimation { viewModel.delete(list: list) }
                }
                listToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete the list '\(listToDelete?.name ?? "this list")'? This action cannot be undone.")
        }
    }
    
    private func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        let customDateFormat = GlobalState.dateFormat

        if !customDateFormat.isEmpty {
            let timeTemplate = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: Locale.current) ?? "HH:mm"
            formatter.dateFormat = "\(customDateFormat) \(timeTemplate)"
        } else {
            formatter.dateStyle = .long
            formatter.timeStyle = .short
        }
        
        return formatter.string(from: date)
    }
    
    private func row(for list: ShoppingListModel) -> some View {
        HStack(spacing: 15) {
            Image(systemName: list.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(list.isCompleted ? .green : effectManager.currentGlobalAccentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(list.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .strikethrough(list.isCompleted, color: effectManager.currentGlobalAccentColor.opacity(0.8))
                    .lineLimit(1)
                
                Text("Created: \(formattedDate(from: list.creationDate))")
                    .font(.subheadline)
                    .strikethrough(list.isCompleted, color: effectManager.currentGlobalAccentColor.opacity(0.8))
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                
                Text("Items: \(list.items.count) | Total: \(list.totalPrice, format: .currency(code: GlobalState.currencyCode))")
                    .font(.subheadline)
                    .strikethrough(list.isCompleted, color: effectManager.currentGlobalAccentColor.opacity(0.8))
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .opacity(list.isCompleted ? 0.6 : 1.0)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private func presentStartupListIfNeeded(animate: Bool = true) {
        guard !hasPresentedStartupList, listToPresent == nil else {
            if listToPresent != nil { hasPresentedStartupList = true }
            return
        }
        hasPresentedStartupList = true
        var listToOpen: ShoppingListModel? = nil

        if let lastID = viewModel.lastOpenedListID, let lastOpened = viewModel.lists.first(where: { $0.id == lastID }) {
            listToOpen = lastOpened
        } else if let unfinished = viewModel.lists.first(where: { !$0.isCompleted }) {
            listToOpen = unfinished
            viewModel.recordLastOpened(unfinished)
        } else {
            let profileForList = profile.hasSeparateStorage ? profile : nil
            listToOpen = ShoppingListModel(profile: profileForList, name: "New Shopping List")
            viewModel.recordLastOpened(listToOpen!)
        }
        
        if let list = listToOpen {
            if animate {
                present(list: list)
            } else {
                listToPresent = list
            }
        }
    }
    
    // MARK: - Floating Add Button & Gestures

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
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspectRatio = size.height / size.width
        return aspectRatio > 1.9 ? 75 : 95
    }

    private func trailingPadding(for geometry: GeometryProxy) -> CGFloat {
        return 45
    }
    
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
    
    private func handleButtonTap() {
        let profileForList = profile.hasSeparateStorage ? profile : nil
        let newList = ShoppingListModel(profile: profileForList, name: "New Shopping List")
        present(list: newList)
    }
    
    private func present(list: ShoppingListModel) {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAddButtonVisible = false
            listToPresent = list
        }
        
        viewModel.recordLastOpened(list)
        if isSearching {
            onShouldDismissGlobalSearch()
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
}

// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/ShoppingList/Views/ShoppingListDetailView.swift ====
import SwiftUI
import SwiftData
import EventKit
import Combine
import UserNotifications

struct ShoppingListDetailView: View {
    @Binding var navBarIsHiden: Bool
    
    // --- Floating Scan Button state ---
    @State private var isScanDragging: Bool = false
    @GestureState private var scanGestureOffset: CGSize = .zero
    @State private var scanButtonOffset: CGSize = .zero
    @State private var isScanPressed: Bool = false
    private let scanButtonPositionKey = "floatingScanButtonPosition"
    
    @State private var isShowingScanMenu: Bool = false
    @State private var scanMenuState: MenuState = .collapsed

    // MARK: - Environment & Managers
    @FocusState.Binding var isSearchFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @ObservedObject private var effectManager = EffectManager.shared
    private let reminderOptions = [0, 5, 10, 15, 30, 60]

    // MARK: - Original Model & Dependencies
    let list: ShoppingListModel
    @ObservedObject var viewModel: ShoppingListViewModel
    let isNew: Bool
    @Binding var globalSearchText: String
    @Binding var isSearching: Bool
    let onDismiss: () -> Void
    let onDismissSearch: () -> Void
    let onShowCalendar: (Date) -> Void

    // MARK: - Local Editable State (The "Copy")
    @State private var editableName: String
    @State private var editableStartDate: Date
    @State private var editableReminderOffset: Int
    @State private var editableItems: [EditableShoppingListItem]

    // MARK: - View State
    @State private var initiallyBoughtItemIDs: Set<UUID> = []
    @State private var hasBeenSaved: Bool = false
    @State private var isShowingDeleteItemConfirmation = false
    @State private var itemToDelete: EditableShoppingListItem? = nil
    
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    // MARK: - Focus State
    enum FocusableField: Hashable {
        case quantity(id: UUID)
        case price(id: UUID)
        case listName
        case search
    }
    @FocusState private var focusedField: FocusableField?

    // MARK: - AppStorage for Last Prices
    @AppStorage("ShoppingListLastPrices") private var lastPricesData: Data = Data()
    @State private var lastPrices: [Int: Double] = [:]

    // MARK: - Helper Struct for Editable Items
    private struct EditableShoppingListItem: Identifiable, Hashable {
        let id: UUID
        let originalID: UUID?
        var name: String
        var quantity: Double
        var price: Double?
        var isBought: Bool
        let foodItem: FoodItem?

        init(from item: ShoppingListItem) {
            self.id = UUID()
            self.originalID = item.id
            self.name = item.name
            self.quantity = item.quantity
            self.price = item.price
            self.isBought = item.isBought
            self.foodItem = item.foodItem
        }
        
        init(from food: FoodItem, quantity: Double, price: Double?) {
            self.id = UUID()
            self.originalID = nil
            self.name = food.name
            self.quantity = quantity
            self.price = price
            self.isBought = false
            self.foodItem = food
        }
    }

    // MARK: - Initializer
    init(
            list: ShoppingListModel,
            viewModel: ShoppingListViewModel,
            isNew: Bool = false,
            globalSearchText: Binding<String>,
            isSearching: Binding<Bool>,
            onDismiss: @escaping () -> Void,
            onDismissSearch: @escaping () -> Void,
            onShowCalendar: @escaping (Date) -> Void,
            isSearchFieldFocused: FocusState<Bool>.Binding,
            navBarIsHiden: Binding<Bool>
        ) {
            self.list = list
            self.viewModel = viewModel
            self.isNew = isNew
            self._globalSearchText = globalSearchText
            self._isSearching = isSearching
            self.onDismiss = onDismiss
            self.onDismissSearch = onDismissSearch
            self.onShowCalendar = onShowCalendar
            self._isSearchFieldFocused = isSearchFieldFocused
            self._navBarIsHiden = navBarIsHiden

        _editableName = State(initialValue: list.name)
        _editableStartDate = State(initialValue: list.eventStartDate)
        _editableReminderOffset = State(initialValue: list.reminderMinutes ?? 0)
        _editableItems = State(initialValue: list.items.map { EditableShoppingListItem(from: $0) })
        _lastPrices = State(initialValue: (try? JSONDecoder().decode([Int: Double].self, from: lastPricesData)) ?? [:])
    }
    
    // MARK: - Computed Properties
    private var sortedItems: [EditableShoppingListItem] {
        editableItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var totalPrice: Double {
        editableItems.reduce(0) { $0 + ($1.price ?? 0) }
    }
    
    private var purchasedPrice: Double {
        editableItems.filter(\.isBought).reduce(0) { $0 + ($1.price ?? 0) }
    }
    
    private var areAllItemsBought: Bool {
        !editableItems.isEmpty && editableItems.allSatisfy { $0.isBought }
    }

    private var isSaveDisabled: Bool {
        let currentReminder = editableReminderOffset == 0 ? nil : editableReminderOffset
        let hasCoreChanges = editableName != list.name ||
                             editableStartDate != list.eventStartDate ||
                             currentReminder != list.reminderMinutes

        let originalItems = list.items.map { EditableShoppingListItem(from: $0) }
        let hasItemChanges: Bool
        if editableItems.count != originalItems.count {
            hasItemChanges = true
        } else {
            var itemContentChanged = false
            for editableItem in editableItems {
                if let originalItem = originalItems.first(where: { $0.originalID == editableItem.originalID }) {
                    if abs(editableItem.quantity - originalItem.quantity) > 0.001 ||
                       editableItem.price != originalItem.price ||
                       editableItem.isBought != originalItem.isBought {
                        itemContentChanged = true
                        break
                    }
                } else {
                    itemContentChanged = true
                    break
                }
            }
            hasItemChanges = itemContentChanged
        }

        return !hasCoreChanges && !hasItemChanges
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            mainContent

            // --- ✅ НОВ ПАНЕЛ ЗА ТЪРСЕНЕ ---
            if isSearchFieldFocused {
                // Създаваме Binding за фокуса, който се управлява от FoodSearchPanelView
                let focusBinding = Binding<Bool>(
                    get: { isSearchFieldFocused },
                    set: { isSearchFieldFocused = $0 }
                )
                
                // Изчисляваме кои ID-та да скрием (тези, които вече са в списъка)
                let excludedIDs = Set(editableItems.compactMap { $0.foodItem?.id })
                
                FoodSearchPanelView(
                    globalSearchText: $globalSearchText,
                    isSearchFieldFocused: focusBinding,
                    profile: viewModel.profile,
                    // Може да бъде .recipes или nil (за всички), според предпочитанията
                    searchMode: .recipes,
                    showFavoritesFilter: true,
                    showRecipesFilter: false, // Скрито, ако searchMode е фиксиран
                    showMenusFilter: false,
                    headerRightText: nil,
                    excludedFoodIDs: excludedIDs, // ✅ Подаваме изключените ID-та
                    onSelectFood: { foodItem in
                        addFoodItem(foodItem)
                    },
                    onDismiss: {
                        dismissKeyboardAndSearch()
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(1)
            }
            // -------------------------------------

            GeometryReader { geometry in
                 if !isSearchFieldFocused {
                     scanButton(geometry: geometry)
                         .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                         .padding(.trailing, scanTrailingPadding(for: geometry))
                         .padding(.bottom, scanBottomPadding(for: geometry))
                 }
             }
             .ignoresSafeArea(.keyboard, edges: .bottom)
            
            if isShowingScanMenu {
                ZStack {
                    (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            scanMenuState = .collapsed
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowingScanMenu = false
                            }
                        }

                    DraggableMenuView(
                        menuState: $scanMenuState,
                        removeBottomPading: true,
                        customTopGap: UIScreen.main.bounds.height * 0.08,
                        horizontalContent: { EmptyView() },
                        verticalContent: {
                            BarcodeScannerView(
                                mode: .shoppingList,
                                profile: viewModel.profile,
                                onBarcodeSelect: { entity in
                                    handleScannedBarcode(entity)
                                },
                                onAddFoodItem: { foodItem in
                                    addFoodItem(foodItem)
                                }
                            )
                        },
                        onStateChange: { newState in
                            if newState == .collapsed {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isShowingScanMenu = false
                                }
                            }
                        }
                    )
                    .edgesIgnoringSafeArea(.all)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowingScanMenu)
            }
        }
        .onChange(of: isShowingScanMenu) { _, newValue in
                   navBarIsHiden = newValue
               }
        .onAppear {
            viewModel.setup(context: modelContext)
            
            if !hasBeenSaved {
                initiallyBoughtItemIDs = Set(list.items.filter { $0.isBought }.map { $0.id })
            }

            reloadLastPricesFromAppStorage()
            checkNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkNotificationStatus()
        }
        .onDisappear {
            if !hasBeenSaved {
                if isNew { modelContext.delete(list) }
            }
        }
        .onChange(of: lastPricesData) { _, _ in
            reloadLastPricesFromAppStorage()
        }
        .alert("Delete Item", isPresented: $isShowingDeleteItemConfirmation) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete { deleteItem(item) }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("Are you sure you want to delete '\(itemToDelete?.name ?? "this item")' from the list? This action cannot be undone.")
        }
    }
    
    private func checkNotificationStatus() {
        Task {
            let status = await NotificationManager.shared.getAuthorizationStatus()
            await MainActor.run {
                withAnimation {
                    self.notificationStatus = status
                }
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            customToolbar
                .padding(.horizontal)

            ScrollViewReader { proxy in
                List {
                    listInfoSection
                    itemsSection
                    suggestionsSection
                        .disabled(areAllItemsBought)
                        .opacity(areAllItemsBought ? 0.6 : 1.0)

                    Color.clear
                        .frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onChange(of: focusedField) { _, newFocus in
                    guard let focus = newFocus else { return }
                    
                    let itemID: UUID?
                    switch focus {
                    case .quantity(let id):
                        itemID = id
                    case .price(let id):
                        itemID = id
                    default:
                        itemID = nil
                    }

                    if let idToScroll = itemID {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(idToScroll, anchor: .top)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var customToolbar: some View {
        HStack {
            Button {
                cancelChanges()
            } label: {
                HStack { Image(systemName: "chevron.backward"); Text("All Lists") }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Purchased:").font(.caption).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text("\(purchasedPrice, format: .currency(code: GlobalState.currencyCode))").font(.caption.bold()).foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                HStack(spacing: 4) {
                    Text("Total:").font(.caption).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text("\(totalPrice, format: .currency(code: GlobalState.currencyCode))").font(.caption.bold()).foregroundStyle(effectManager.currentGlobalAccentColor)
                }
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                Button { onShowCalendar(editableStartDate) } label: {
                    Image(systemName: "calendar").font(.title3).padding(8)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                Divider().frame(height: 20).padding(.horizontal, 4)
                
                Button("Save", action: saveChanges)
                    .disabled(isSaveDisabled)
                    .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
                    .padding(.trailing, 10).padding(.leading, 2).padding(.vertical, 5)
            }
            .glassCardStyle(cornerRadius: 20)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    private var listInfoSection: some View {
        Section {
            VStack(spacing: 12) {
                TextField("", text: $editableName, prompt: Text("Friday market").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                    .focused($focusedField, equals: .listName)
                    .font(.system(size: 16))
                    .onSubmit { focusedField = nil
                    }
                    .disableAutocorrection(true)
                

                HStack {
                    Text("Date & Time")
                    Spacer()
                    CustomDatePicker(selection: $editableStartDate, tintColor: UIColor(effectManager.currentGlobalAccentColor), textColor: .label)
                        .frame(height: 40)
                    CustomTimePicker(selection: $editableStartDate, textColor: .label)
                        .frame(height: 40)
                }

                if notificationStatus == .denied {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reminder")
                            Spacer()
                            Text("Notifications are disabled. Please enable them in Settings.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                    }
                } else {
                    HStack {
                        Text("Reminder")
                        Spacer()
                        Picker("", selection: $editableReminderOffset) {
                            ForEach(reminderOptions, id: \.self) { minutes in
                                Text(formatReminder(minutes)).tag(minutes)
                            }
                        }
                        .tint(effectManager.currentGlobalAccentColor)
                    }
                }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    @ViewBuilder
    private var itemsSection: some View {
        HStack {
            Text("Items")
                .textCase(.none)
                .font(.headline)
            Spacer()
            if !editableItems.isEmpty {
                Button(areAllItemsBought ? "Deselect Newly Bought" : "Mark All As Bought", action: toggleAllItemsBought)
                    .textCase(.none)
                    .font(.headline)
            }
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))

        // Проверка: ако списъкът е празен и не се търси нищо
        if editableItems.isEmpty && globalSearchText.isEmpty {
            Text("The list is empty. Add items from suggestions or use search.")
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding()
                .frame(maxWidth: .infinity)
                .glassCardStyle(cornerRadius: 20)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else {
            ForEach(sortedItems) { item in
                let itemBinding = Binding<EditableShoppingListItem>(
                    get: {
                        editableItems.first { $0.id == item.id } ?? item
                    },
                    set: { newItem in
                        if let index = editableItems.firstIndex(where: { $0.id == item.id }) {
                            editableItems[index] = newItem
                        }
                    }
                )
                
                let itemView = shoppingListItemView(for: itemBinding)
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .id(item.id)

                if item.isBought {
                    itemView
                } else {
                    itemView.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if #available(iOS 26.0, *) {
                                deleteItem(item)
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
        }
    }
    
    private func shoppingListItemView(for itemBinding: Binding<EditableShoppingListItem>) -> some View {
        let item = itemBinding.wrappedValue
        
        return HStack(spacing: 12) {
            Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(item.isBought ? .green : effectManager.currentGlobalAccentColor)
                .contentShape(Rectangle())
                .onTapGesture {
                    if initiallyBoughtItemIDs.contains(where: { $0 == item.originalID }) == false {
                        withAnimation {
                            itemBinding.wrappedValue.isBought.toggle()
                        }
                    }
                }

            Text(item.name)
                .strikethrough(item.isBought, color: effectManager.currentGlobalAccentColor.opacity(0.8))
                .opacity(item.isBought ? 0.8 : 1.0)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                quantityField(for: itemBinding)
                priceField(for: itemBinding)
            }
            .disabled(item.isBought)
        }
        .disabled(areAllItemsBought && !item.isBought)
    }

    @ViewBuilder
    private func quantityField(for itemBinding: Binding<EditableShoppingListItem>) -> some View {
        let optionalQuantityBinding = Binding<Double?>(
            get: { itemBinding.wrappedValue.quantity },
            set: { newValue in
                if let newQuantity = newValue {
                    itemBinding.wrappedValue.quantity = newQuantity
                }
            }
        )

        let isImperial = GlobalState.measurementSystem == "Imperial"
        let unitString = (itemBinding.wrappedValue.foodItem != nil) ? (isImperial ? "oz" : "g") : ""

        ShoppingItemEditableField(
            value: optionalQuantityBinding,
            unit: unitString,
            focusedField: $focusedField,
            focusCase: .quantity(id: itemBinding.wrappedValue.id),
            isInteger: false,
            maxValue: 30000.0,
            usesUnitConversion: itemBinding.wrappedValue.foodItem != nil
        )
            .strikethrough(itemBinding.wrappedValue.isBought, color: effectManager.currentGlobalAccentColor.opacity(0.8))
            .opacity(itemBinding.wrappedValue.isBought ? 0.8 : 1.0)
            .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    @ViewBuilder
    private func priceField(for itemBinding: Binding<EditableShoppingListItem>) -> some View {
        ShoppingItemEditableField(
            value: itemBinding.price,
            unit: GlobalState.currencyCode,
            focusedField: $focusedField,
            focusCase: .price(id: itemBinding.wrappedValue.id),
            maxValue: 30000.0,
            usesUnitConversion: false,
            onFinalValue: { finalPrice in
                if let price = finalPrice, let foodItemID = itemBinding.wrappedValue.foodItem?.id {
                    lastPrices[foodItemID] = price
                }
            }
        )
        .strikethrough(itemBinding.wrappedValue.isBought, color: effectManager.currentGlobalAccentColor.opacity(0.8))
        .opacity(itemBinding.wrappedValue.isBought ? 0.8 : 1.0)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }
    
    @ViewBuilder
    private var suggestionsSection: some View {
        if !combinedSuggestions.isEmpty {
            Text("Suggestions")
                .textCase(.none).font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
            ForEach(combinedSuggestions) { food in
                HStack {
                    VStack(alignment: .leading) {
                        Text(food.name)
                        if let storageItem = viewModel.suggestedItems.first(where: { $0.food?.id == food.id }) {
                            Text("Low stock: \(Int(storageItem.totalQuantity)) g").font(.caption).foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        } else {
                            Text("Recently used").font(.caption).foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
                    }.foregroundColor(effectManager.currentGlobalAccentColor)
                    Spacer()
                    HStack(spacing: 15) {
                        Button(action: { dismissSuggestion(food: food) }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                        Button(action: { addSuggestedItem(food: food) }) { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                    }.font(.title2).buttonStyle(.plain)
                }
                .padding().glassCardStyle(cornerRadius: 20)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }

    private func saveChanges() {
        hideKeyboard()
        
        list.name = editableName
        list.eventStartDate = editableStartDate
        list.reminderMinutes = editableReminderOffset == 0 ? nil : editableReminderOffset
        list.isCompleted = areAllItemsBought

        let editableItemOriginalIDs = Set(editableItems.compactMap { $0.originalID })
        list.items.removeAll { item in !editableItemOriginalIDs.contains(item.id) }
        
        for editableItem in editableItems {
            if let originalID = editableItem.originalID, let existingItem = list.items.first(where: { $0.id == originalID }) {
                existingItem.quantity = editableItem.quantity
                existingItem.price = editableItem.price
                existingItem.isBought = editableItem.isBought
            } else {
                let newItem = ShoppingListItem(name: editableItem.name, quantity: editableItem.quantity, price: editableItem.price, isBought: editableItem.isBought, foodItem: editableItem.foodItem)
                list.items.append(newItem)
            }
        }
        
        if isNew && !hasBeenSaved {
            modelContext.insert(list)
        }

        do { try viewModel.processCompletedItems(for: list, initiallyBoughtIDs: initiallyBoughtItemIDs) }
        catch { print("Error processing completed items: \(error)") }

        Task { @MainActor in
            if let oldID = list.notificationID { NotificationManager.shared.cancelNotification(id: oldID); list.notificationID = nil }
            if let minutes = list.reminderMinutes, minutes > 0 {
                let reminderDate = list.eventStartDate.addingTimeInterval(-TimeInterval(minutes * 60))
                if reminderDate.timeIntervalSinceNow > 0 {
                    do {
                        let newID = try await NotificationManager.shared.scheduleNotification(
                            title: "🛒 Shopping Reminder",
                            body: "Time to buy groceries for your list: \(list.name)",
                            timeInterval: reminderDate.timeIntervalSinceNow,
                            userInfo: ["shoppingListID": list.id.uuidString],
                            profileID: viewModel.profile.id
                        )
                        list.notificationID = newID
                    } catch { print("Error scheduling notification: \(error)") }
                }
            }
            list.calendarEventID = await CalendarViewModel.shared.createOrUpdateShoppingListEvent(for: list, context: modelContext)
            if modelContext.hasChanges { try? modelContext.save() }
        }

        do {
            if modelContext.hasChanges { try? modelContext.save() }
            hasBeenSaved = true
            initiallyBoughtItemIDs = Set(list.items.filter { $0.isBought }.map { $0.id })
            viewModel.fetchAllData()
            
            do { lastPricesData = try JSONEncoder().encode(lastPrices) } catch { print("Failed to encode prices: \(error)") }
            onDismiss()
        } catch { print("Final save error: \(error)") }
    }

    private func cancelChanges() {
        hideKeyboard()
        if isNew && !hasBeenSaved { modelContext.delete(list) }
        onDismiss()
    }
    
    private func hideKeyboard() { focusedField = nil; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func dismissSuggestion(food: FoodItem) { withAnimation { list.addDismissedSuggestion(foodID: food.id, context: modelContext); viewModel.fetchAllData() } }
    private func deleteItem(_ item: EditableShoppingListItem) { withAnimation { editableItems.removeAll { $0.id == item.id } } }
    private func toggleAllItemsBought() {
        let actionIsMarkAll = !areAllItemsBought
        for i in editableItems.indices {
            if initiallyBoughtItemIDs.contains(where: { $0 == editableItems[i].originalID }) == false {
                if editableItems[i].isBought != actionIsMarkAll { editableItems[i].isBought = actionIsMarkAll }
            }
        }
    }
    
    private func hasFoodInList(_ food: FoodItem) -> Bool {
        editableItems.contains { $0.foodItem?.id == food.id }
    }
    
    private func addFoodItem(_ food: FoodItem) {
        guard !hasFoodInList(food) else {
            dismissKeyboardAndSearch()
            return
        }

        let isImperial = GlobalState.measurementSystem == "Imperial"
        let defaultQuantity = isImperial ? UnitConversion.ozToG(4.0) : 100.0
        let defaultPrice = lastPrices[food.id]
        withAnimation {
            editableItems.insert(EditableShoppingListItem(from: food, quantity: defaultQuantity, price: defaultPrice), at: 0)
        }
        dismissKeyboardAndSearch()
        viewModel.fetchAllData()
    }

    private func addSuggestedItem(food: FoodItem) {
        guard !hasFoodInList(food) else { return }

        let isImperial = GlobalState.measurementSystem == "Imperial"
        let defaultQuantity = isImperial ? UnitConversion.ozToG(4.0) : 100.0
        let defaultPrice = lastPrices[food.id]
        withAnimation {
            editableItems.insert(EditableShoppingListItem(from: food, quantity: defaultQuantity, price: defaultPrice), at: 0)
        }
        viewModel.fetchAllData()
    }

    private func formatReminder(_ minutes: Int) -> String { if minutes == 0 { return "None" }; return "\(minutes) min before" }
    
    private var combinedSuggestions: [FoodItem] {
        let lowStockFoods = viewModel.suggestedItems.compactMap { $0.food }
        let recentFoods = viewModel.recentFoodItems
        var uniqueFoods: [Int: FoodItem] = [:]
        for food in lowStockFoods { uniqueFoods[food.id] = food }
        for food in recentFoods { uniqueFoods[food.id] = food }
        let allUniqueSuggestions = Array(uniqueFoods.values).sorted { $0.name < $1.name }
        let currentListFoodItemIDs = Set(editableItems.compactMap { $0.foodItem?.id })
        return allUniqueSuggestions.filter { !list.isSuggestionDismissed(foodID: $0.id) && !currentListFoodItemIDs.contains($0.id) }
    }
    
    private func dismissKeyboardAndSearch() { isSearchFieldFocused = false; globalSearchText = "" }
    
    private func reloadLastPricesFromAppStorage() {
        if let decoded = try? JSONDecoder().decode([Int: Double].self, from: lastPricesData) { lastPrices = decoded }
        else { lastPrices = [:] }
    }
    
    // MARK: - Floating Scan Button & Gestures

    private func scanDragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($scanGestureOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.isScanPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.isScanDragging = true
                }
            }
            .onEnded { value in
                self.isScanPressed = false
                if isScanDragging {
                    var newOffset = self.scanButtonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height

                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top
                    let maxY = -25 + safeArea.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))

                    self.scanButtonOffset = newOffset
                    self.saveScanButtonPosition()
                } else {
                    self.handleScanButtonTap()
                }
                self.isScanDragging = false
            }
    }

    private func scanBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspectRatio = size.height / size.width
        return aspectRatio > 1.9 ? 75 : 95
    }

    private func scanTrailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }

    @ViewBuilder
    private func scanButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(
            width: scanButtonOffset.width + scanGestureOffset.width,
            height: scanButtonOffset.height + scanGestureOffset.height
        )
        let scale = isScanDragging ? 1.15 : (isScanPressed ? 0.9 : 1.0)

        ZStack {
            Image(systemName: "barcode.viewfinder")
                .font(.title3)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: 60, height: 60)
        .glassCardStyle(cornerRadius: 32)
        .scaleEffect(scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isScanDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isScanPressed)
        .contentShape(Rectangle())
        .offset(currentOffset)
        .gesture(scanDragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
        .onAppear { loadScanButtonPosition() }
    }

    private func handleScanButtonTap() {
        if isSearchFieldFocused {
            dismissKeyboardAndSearch()
        } else {
            hideKeyboard()
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            isShowingScanMenu = true
            scanMenuState = .full
        }
    }
    
    private func handleScannedBarcode(_ entity: DetectedObjectEntity) {
        print("SCANNED: \(entity.title)")
        // Тук в бъдеще ще интегрирате търсене по баркод в базата данни
    }

    private func saveScanButtonPosition() {
        let defaults = UserDefaults.standard
        defaults.set(scanButtonOffset.width, forKey: "\(scanButtonPositionKey)_width")
        defaults.set(scanButtonOffset.height, forKey: "\(scanButtonPositionKey)_height")
    }

    private func loadScanButtonPosition() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "\(scanButtonPositionKey)_width")
        let height = defaults.double(forKey: "\(scanButtonPositionKey)_height")
        self.scanButtonOffset = CGSize(width: width, height: height)
    }
}

import SwiftUI
import SwiftData

struct StorageEditorView: View {
    let owner: Profile
    @Binding var globalSearchText: String
    let onDismiss: (_ shouldDismissGlobalSearch: Bool) -> Void
    @ObservedObject private var effectManager = EffectManager.shared

    @Environment(\.modelContext) private var modelContext

    @State private var productsToAdd: [EditableProduct] = []

    @FocusState private var focusedBatchID: UUID?
    let onShouldDismissGlobalSearch: () -> Void
    let onShouldActivateGlobalSearch: () -> Void

    @Binding var isSearching: Bool
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/4): Коригираме декларацията ---
    var isSearchFieldFocused: FocusState<Bool>.Binding

    private var isFormValid: Bool {
        productsToAdd.contains { product in
            !product.isMarkedForDeletion && product.batches.contains { !$0.isMarkedForDeletion && $0.quantityValue > 0 }
        }
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА (2/4): Коригираме init ---
    init(
        owner: Profile,
        globalSearchText: Binding<String>,
        onDismiss: @escaping (_ shouldDismissGlobalSearch: Bool) -> Void,
        onShouldDismissGlobalSearch: @escaping () -> Void,
        onShouldActivateGlobalSearch: @escaping () -> Void,
        isSearching: Binding<Bool>,
        isSearchFieldFocused: FocusState<Bool>.Binding
    ) {
        self.owner = owner
        self._globalSearchText = globalSearchText
        self.onDismiss = onDismiss
        self.onShouldDismissGlobalSearch = onShouldDismissGlobalSearch
        self.onShouldActivateGlobalSearch = onShouldActivateGlobalSearch
        self._isSearching = isSearching
        self.isSearchFieldFocused = isSearchFieldFocused
    }
    // --- КРАЙ НА ПРОМЯНАТА (2/4) ---

    var body: some View {
        ZStack {
            ThemeBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach($productsToAdd) { $product in
                                if !product.isMarkedForDeletion {
                                    ProductCard(
                                        product: $product,
                                        focusedBatchID: $focusedBatchID,
                                        onDeleteProduct: { deleteProduct(withId: product.id) },
                                        onAddBatch: { addBatch(to: $product) },
                                        onDeleteBatch: { batchId in deleteBatch(withId: batchId, fromProductWithId: product.id) },
                                        onShouldDismissGlobalSearch: onShouldDismissGlobalSearch
                                    )
                                    .id(product.id)
                                    .glassCardStyle(cornerRadius: 20)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .leading),
                                            removal: .move(edge: .trailing)
                                        )
                                        .combined(with: .opacity)
                                    )
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, isSearchFieldFocused.wrappedValue ? UIScreen.main.bounds.height * 0.5 : 0)
                        
                        Spacer(minLength: 150)
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
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedBatchID) { oldValue, newValue in
                        if let oldID = oldValue, newValue != oldID {
                            formatFocusedBatch(withId: oldID)
                        }

                        guard let newID = newValue else { return }

                        if let product = productsToAdd.first(where: { $0.batches.contains(where: { $0.id == newID }) }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(product.id, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            
            if isSearchFieldFocused.wrappedValue {
                let focusBinding = Binding<Bool>(
                    get: { isSearchFieldFocused.wrappedValue },
                    set: { isSearchFieldFocused.wrappedValue = $0 }
                )
                
                // ✅ НОВО: Изчисляваме кои ID-та да скрием.
                // Взимаме само тези, които НЕ са маркирани за изтриване.
                let excludedIDs = Set(
                    productsToAdd
                        .filter { !$0.isMarkedForDeletion }
                        .map { $0.food.id }
                )
                
                FoodSearchPanelView(
                    globalSearchText: $globalSearchText,
                    isSearchFieldFocused: focusBinding,
                    profile: owner,
                    searchMode: .menus,
                    showFavoritesFilter: true,
                    showRecipesFilter: true,
                    showMenusFilter: false,
                    excludedFoodIDs: excludedIDs,
                    onSelectFood: { foodItem in
                        addProduct(foodItem)
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideKeyboard()
                            isSearchFieldFocused.wrappedValue = false
                            globalSearchText = ""
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - Toolbar
    private var customToolbar: some View {
        HStack {
            HStack {
                Button("Cancel") {
                    hideKeyboard()
                    onDismiss(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            Text("Add to Storage")
                .fontWeight(.bold)
            
            Spacer()
            
            HStack {
                Button("Save") {
                    saveItemsToContext()
                    hideKeyboard()
                    onDismiss(true)
                }
                .disabled(!isFormValid)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    // MARK: - Actions / Helpers
    private func addProduct(_ food: FoodItem) {
        if let index = productsToAdd.firstIndex(where: { $0.food.id == food.id && $0.isMarkedForDeletion }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                productsToAdd[index].isMarkedForDeletion = false
                if let firstBatchIndex = productsToAdd[index].batches.firstIndex(where: { $0.isMarkedForDeletion }) {
                    productsToAdd[index].batches[firstBatchIndex].isMarkedForDeletion = false
                }
            }
        } else if !productsToAdd.contains(where: { $0.food.id == food.id }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                productsToAdd.insert(EditableProduct(food: food), at: 0)
            }
        }
        
        globalSearchText = ""
        isSearchFieldFocused.wrappedValue = false
        hideKeyboard()
    }
    
    private func addBatch(to product: Binding<EditableProduct>) {
        withAnimation(.easeInOut(duration: 0.3)) {
            product.wrappedValue.batches.append(EditableBatch())
        }
    }

    private func deleteProduct(withId id: UUID) {
        hideKeyboard()
        if let index = productsToAdd.firstIndex(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                productsToAdd[index].isMarkedForDeletion = true
            }
        }
    }
    
    private func deleteBatch(withId batchId: UUID, fromProductWithId productId: UUID) {
        focusedBatchID = nil
        guard let productIndex = productsToAdd.firstIndex(where: { $0.id == productId }) else { return }
        
        if let batchIndex = productsToAdd[productIndex].batches.firstIndex(where: { $0.id == batchId }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                let visibleBatches = productsToAdd[productIndex].batches.filter { !$0.isMarkedForDeletion }
                if visibleBatches.count <= 1 {
                    productsToAdd[productIndex].isMarkedForDeletion = true
                } else {
                    productsToAdd[productIndex].batches[batchIndex].isMarkedForDeletion = true
                }
            }
        }
    }
    
    private func saveItemsToContext() {
        if let focusedID = focusedBatchID {
            formatFocusedBatch(withId: focusedID)
        }
        
        let profileToUseForOwnership = owner.hasSeparateStorage ? owner : nil
        
        let productsToSave = productsToAdd.filter { !$0.isMarkedForDeletion }
        
        for product in productsToSave {
            let storageItem = findExistingStorageItem(for: product.food, ownerProfile: profileToUseForOwnership) ?? StorageItem(owner: profileToUseForOwnership, food: product.food)
            
            if storageItem.owner != profileToUseForOwnership {
                storageItem.owner = profileToUseForOwnership
            }
            if storageItem.modelContext == nil {
                modelContext.insert(storageItem)
            }
            
            let batchesToSave = product.batches.filter { !$0.isMarkedForDeletion }

            for batch in batchesToSave {
                let newBatch = Batch(quantity: batch.quantityValue, expirationDate: batch.hasExpiration ? batch.expirationDate : nil)
                storageItem.batches.append(newBatch)
                
                let transaction = StorageTransaction(
                    date: Date(),
                    type: .addition,
                    quantityChange: batch.quantityValue,
                    profile: profileToUseForOwnership,
                    food: product.food
                )
                modelContext.insert(transaction)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save stock items: \(error)")
        }
    }
    
    private func findExistingStorageItem(for food: FoodItem, ownerProfile: Profile?) -> StorageItem? {
        let foodID = food.persistentModelID
        let profileID = ownerProfile?.persistentModelID
        
        let descriptor = FetchDescriptor<StorageItem>(predicate: #Predicate {
            $0.food?.persistentModelID == foodID && $0.owner?.persistentModelID == profileID
        })
        return try? modelContext.fetch(descriptor).first
    }
    
    private func formatFocusedBatch(withId id: UUID) {
        for pIndex in productsToAdd.indices {
            if let bIndex = productsToAdd[pIndex].batches.firstIndex(where: { $0.id == id }) {
                
                let grams = productsToAdd[pIndex].batches[bIndex].quantityValue
                
                let isImperial = GlobalState.measurementSystem == "Imperial"
                let displayValue = isImperial
                    ? UnitConversion.gToOz_display(grams)
                    : grams
                
                let formattedString = UnitConversion.formatDecimal(displayValue)
                productsToAdd[pIndex].batches[bIndex].quantityString = formattedString
                
                return
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        focusedBatchID = nil
    }
}

import SwiftUI
import SwiftData

struct VideoGalleryFoodSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    
    // ✅ Callback: Когато потребителят натисне "Use", връщаме избрания продукт
    var onSelect: ((FoodItem) -> Void)?
    
    // ✅ 1. Смарт търсачката
    @State private var smartSearch: SmartFoodSearch3?
    
    // Данни
    @State private var allMatchingItems: [FoodItem] = []
    @State private var displayedItems: [FoodItem] = []
    
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var isLoading: Bool = true
    
    // ✅ State за избрания елемент (за Full Screen)
    @State private var selectedItemForDetail: FoodItem?
    
    // Пагинация
    private let batchSize = 50
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            
            VStack(spacing: 0) {
                // --- Toolbar ---
                HStack {
                    Button("Close") { dismiss() }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    
                    Spacer()
                    Text("Food Gallery")
                        .font(.headline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    Spacer()
                    Button("Close") { dismiss() }.opacity(0)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .padding()
                
                // --- Search Bar ---
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    
                    ZStack(alignment: .leading) {
                        if searchText.isEmpty {
                            Text("Search foods...")
                                .foregroundColor(effectManager.currentGlobalAccentColor).opacity(0.7)
                                .allowsHitTesting(false)
                        }
                        
                        TextField("", text: $searchText)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                            .onChange(of: searchText) { _, newValue in
                                handleSearchInput(newValue)
                            }
                    }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchTask?.cancel()
                            searchText = ""
                            loadInitialData()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                        }
                    }
                }
                .padding(12)
                .glassCardStyle(cornerRadius: 20)
                .padding(.horizontal).padding(.bottom, 10)
                
                // --- Content ---
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            Color.clear.frame(height: 1).id("top")
                            
                            if displayedItems.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    .padding(.top, 40)
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(displayedItems, id: \.id) { item in
                                        GalleryFoodItemCell(item: item)
                                            .onAppear {
                                                if item.id == displayedItems.last?.id {
                                                    loadMore()
                                                }
                                            }
                                            // ✅ Натискане върху клетката
                                            .onTapGesture {
                                                selectedItemForDetail = item
                                            }
                                    }
                                    
                                    if displayedItems.count < allMatchingItems.count {
                                        ProgressView().padding()
                                    }
                                }
                                .padding(16)
                            }
                            Color.clear.frame(height: 150)
                        }
                        .onChange(of: allMatchingItems) { _, _ in
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                }
            }
        }
        .onAppear {
            setupEngine()
            loadInitialData()
        }
        // ✅ Full Screen Cover
        .fullScreenCover(item: $selectedItemForDetail) { item in
            FoodFullScreenDetailView(item: item) { confirmedItem in
                // Действие при натискане на USE
                selectedItemForDetail = nil // Затваряме детайлния екран
                onSelect?(confirmedItem)    // Връщаме резултата
                dismiss()                   // Затваряме цялата галерия
            }
        }
    }
    
    // MARK: - Logic
    
    private func setupEngine() {
        if smartSearch == nil {
            let container = modelContext.container
            let engine = SmartFoodSearch3(container: container)
            Task { await engine.loadData() }
            self.smartSearch = engine
        }
    }
    
    private func loadInitialData() {
        searchTask?.cancel()
        searchTask = Task { await performSmartSearch(query: "") }
    }
    
    private func handleSearchInput(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled {
                await performSmartSearch(query: query)
            }
        }
    }
    
    private func performSmartSearch(query: String) async {
        guard let engine = smartSearch else { return }
        
        await MainActor.run { self.isLoading = true }
        
        let limit = query.isEmpty ? 2000 : 500
        let results = await engine.searchResults(query: query, limit: limit)
        
        await MainActor.run {
            let filtered = results.filter { item in
                (item.photo != nil) || FoodVideoSource.shared.hasVideo(for: item.id)
            }
            
            self.allMatchingItems = filtered
            self.displayedItems = Array(filtered.prefix(batchSize))
            self.isLoading = false
        }
    }
    
    private func loadMore() {
        guard displayedItems.count < allMatchingItems.count else { return }
        let currentCount = displayedItems.count
        let nextCount = min(currentCount + batchSize, allMatchingItems.count)
        let nextBatch = allMatchingItems[currentCount..<nextCount]
        displayedItems.append(contentsOf: nextBatch)
    }
}

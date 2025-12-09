import SwiftUI
import SwiftData

struct DietDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let diet: Diet
    let profile: Profile?
    let onDismiss: () -> Void
    let onDismissSearch: () -> Void
    @Binding var globalSearchText: String

    @State private var displayItems: [FoodItem] = []

    // Вътрешен детайл без sheet
    @State private var itemForDetailView: FoodItem? = nil

    init(
        diet: Diet,
        profile: Profile?,
        onDismiss: @escaping () -> Void,
        globalSearchText: Binding<String>,
        onDismissSearch: @escaping () -> Void
    ) {
        self.diet = diet
        self.profile = profile
        self.onDismiss = onDismiss
        self._globalSearchText = globalSearchText
        self.onDismissSearch = onDismissSearch
    }

    var body: some View {
        ZStack {
            mainContent
                .opacity(itemForDetailView == nil ? 1 : 0)

            if let item = itemForDetailView {
                FoodItemDetailView(
                    food: item,
                    profile: profile,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            itemForDetailView = nil
                        }
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing),
                                        removal: .move(edge: .trailing)))
                .zIndex(10)
            }
        }
        .background(ThemeBackgroundView().ignoresSafeArea())
        .onAppear {
            onDismissSearch()
            rebuildFromDiet()
        }
        .onChange(of: globalSearchText) { _, _ in
            rebuildFromDiet()
        }
        // ако асоциираните храни на диетата се променят, обнови изгледа
        .onChange(of: (diet.foods ?? []).map(\.id)) { _, _ in
            rebuildFromDiet()
        }
    }

    // MARK: - Main content
    private var mainContent: some View {
        VStack(spacing: 0) {
            customToolbar
                .padding(.horizontal)

            if displayItems.isEmpty && globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView {
                    Label("No Associated Foods", systemImage: "fork.knife.circle")
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                } description: {
                    Text("No foods have been assigned to the \"\(diet.name)\" diet yet.")
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            } else if displayItems.isEmpty {
                ContentUnavailableView.search(text: globalSearchText)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    // ⬇️ добавяме index + реклами, както във FoodItemListView
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 0) {
                            FoodItemRowView(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        itemForDetailView = item
                                    }
                                }
                                .padding(.vertical, 6)

                            if shouldShowAd(at: index) {
                                AdRowView()
                                    .padding(.top, 8)
                                    .padding(.bottom, 8)
                                    .transition(.opacity)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }

                    Color.clear.frame(height: 120)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black,  location: 0.01),
                            .init(color: .black,  location: 0.9),
                            .init(color: .clear,  location: 0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    // MARK: - Toolbar
    private var customToolbar: some View {
        HStack {
            Button(action: onDismiss) {
                HStack {
                    Text("Back")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)

            Spacer()

            Text(diet.name)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            Spacer()

            Button("Back") {}.hidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.top, 10)
    }

    // MARK: - Локално изграждане/филтриране
    private func rebuildFromDiet() {
        let base = (diet.foods ?? [])
        let trimmed = globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            displayItems = base.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return
        }

        let needle = normalized(trimmed)
        displayItems = base
            .filter { normalized($0.name).contains(needle) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    // MARK: - Ad Logic (същата като във FoodItemListView)
    private func shouldShowAd(at index: Int) -> Bool {
        // Premium → без реклами
        if SubscriptionManager.shared.subscriptionStatus != .base {
            return false
        }

        // Пропускаме първите 2 реда
        if index < 2 { return false }

        // Същият pattern: индекси 2, 5, 9, 12, 16, 19...
        let remainder = index % 7
        if remainder == 2 || remainder == 5 {
            return true
        }

        return false
    }
}

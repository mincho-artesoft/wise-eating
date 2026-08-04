import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @StateObject private var manager = SubscriptionManager.shared

    /// Активен таб в SubscriptionView (Base / Remove Ads / Advanced / Premium)
    @Binding var selectedCategory: SubscriptionCategory

    /// RootView задава това, когато потребителят е надхвърлил лимита за профили.
    /// SubscriptionView показва alert и фокусира съответния таб.
    @Binding var pendingUpgradeCategory: SubscriptionCategory?

    @State private var selectedProductID: String?

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var effectManager = EffectManager.shared

    @State private var activeAlert: ActiveAlert?

    private enum ActiveAlert: Identifiable {
        case restore(String)
        case upgrade(String)

        var id: UUID {
            switch self {
            case .restore:
                return UUID(uuidString: "811E13E1-8671-5D43-A0A4-59CBEA8C59F")!
            case .upgrade:
                return UUID(uuidString: "E7BAB2C2-FBF5-560B-BA67-C51C70A3712E")!
            }
        }
    }

    // MARK: - Init

    init(
        selectedCategory: Binding<SubscriptionCategory>,
        pendingUpgradeCategory: Binding<SubscriptionCategory?>
    ) {
        self._selectedCategory = selectedCategory
        self._pendingUpgradeCategory = pendingUpgradeCategory
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                WrappingSegmentedControl(selection: $selectedCategory, layoutMode: .wrap)

                Group {
                    switch selectedCategory {
                    case .base:
                        ScrollView(showsIndicators: false) {
                            BaseSubscriptionView()
                                .padding(.horizontal)
                                .padding(.top, 10)

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

                    case .removeAds:
                        SubscriptionListView(
                            title: "Ads",
                            products: manager.sortedProducts.filter { $0.id.localizedCaseInsensitiveContains("remove.ads") },
                            selectedProductID: $selectedProductID
                        )

                    case .advance:
                        SubscriptionListView(
                            title: "Advanced",
                            products: manager.sortedProducts.filter { $0.id.localizedCaseInsensitiveContains("advanced") },
                            selectedProductID: $selectedProductID
                        )

                    case .premium:
                        SubscriptionListView(
                            title: "Premium",
                            products: manager.sortedProducts.filter { $0.id.localizedCaseInsensitiveContains("premium") },
                            selectedProductID: $selectedProductID
                        )
                    }
                }

                Spacer()
            }
            .padding(.top, 10)
        }
        // когато влезем в Subs таба за пръв път
        .onAppear {
            setupDefaultSelection()
            handlePendingUpgradeIfNeeded()
        }
        // ако се промени селекцията на таба
        .onChange(of: selectedCategory) { _, _ in
            setupDefaultSelection()
        }
        // ако се обновят продуктите от StoreKit
        .onChange(of: manager.products) { _, _ in
            setupDefaultSelection()
        }
        // ако се смени състоянието на абонаментите (покупка/restore)
        .onChange(of: manager.hasActiveSubscription) { _, hasActive in
            if hasActive {
                selectedProductID = manager.purchasedProductIDs.first
            } else {
                setupDefaultSelection()
            }
        }
        // когато приложението стане активно
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await manager.updatePurchasedStatus() }
            }
        }
        // Restore purchases – съобщението идва от SubscriptionManager
        .onChange(of: manager.restorationAlertMessage) { _, newValue in
            if let message = newValue {
                activeAlert = .restore(message)
                manager.restorationAlertMessage = nil
            }
        }
        // 🔥 ТУК: ако pendingUpgradeCategory се промени, обработваме я
        .onChange(of: pendingUpgradeCategory) { _, _ in
            handlePendingUpgradeIfNeeded()
        }
        // Един централен alert за restore и upgrade
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .restore(let msg):
                return Alert(
                    title: Text("Restore Purchases"),
                    message: Text(msg),
                    dismissButton: .default(Text("OK"))
                )

            case .upgrade(let msg):
                return Alert(
                    title: Text("Upgrade Required"),
                    message: Text(msg),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Helpers

    /// Обработва pendingUpgradeCategory – вика се от onAppear и onChange.
    private func handlePendingUpgradeIfNeeded() {
        guard let tier = pendingUpgradeCategory else { return }

        print("🚀 pendingUpgradeCategory received:", tier)

        // Показваме съответния сегмент
        selectedCategory = tier

        let message: String
        switch tier {
        case .advance:
            message = "You have reached the maximum number of profiles for your current plan. To create more profiles, please subscribe to the Advanced plan."
        case .premium:
            message = "You have reached the maximum number of profiles for your current plan. To create more profiles, please subscribe to the Premium plan."
        case .base, .removeAds:
            message = "You have reached the maximum number of profiles for your current plan. Please upgrade your subscription to create more profiles."
        }

        activeAlert = .upgrade(message)
        // Нулираме флага, за да не се показва пак автоматично
        pendingUpgradeCategory = nil
    }

    private func setupDefaultSelection() {
        // Ако сме в Base таба – няма селектиран конкретен продукт
        guard selectedCategory != .base else {
            selectedProductID = nil
            return
        }

        let categoryMatches: (Product) -> Bool = { product in
            switch selectedCategory {
            case .removeAds:
                return product.id.localizedCaseInsensitiveContains("remove.ads")
            case .advance:
                return product.id.localizedCaseInsensitiveContains("advanced")
            case .premium:
                return product.id.localizedCaseInsensitiveContains("premium")
            case .base:
                return false
            }
        }

        if let firstSelectable = manager.sortedProducts.first(where: { product in
            categoryMatches(product)
            && manager.canPurchase(product)
            && !manager.purchasedProductIDs.contains(product.id)
        }) {
            selectedProductID = firstSelectable.id
        } else {
            selectedProductID = manager.sortedProducts.first(where: categoryMatches)?.id
        }
    }
}

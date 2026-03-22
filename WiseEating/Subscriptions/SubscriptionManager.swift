import SwiftUI
import StoreKit
import UIKit

typealias StoreTransaction = StoreKit.Transaction

@MainActor
class SubscriptionManager: ObservableObject {
    @AppStorage("subscriptionStatus") private var subscriptionStatusRaw: String = SubscriptionStatus.base.rawValue
    @Published var restorationAlertMessage: String?

    // --- НОВО: Състояние за банера, валидно само за текущата сесия ---
    @Published var isPlanBannerDismissed: Bool = false
    // --- КРАЙ НА НОВОТО ---

    static let promoEndDate: Date = {
               var comps = DateComponents()
               comps.year = 2021
               comps.month = 4  // Април
               comps.day = 1    // 1-ви
               comps.hour = 23
               comps.minute = 59
               return Calendar.current.date(from: comps) ?? Date.distantFuture
           }()
        
        // Помощна променлива
        var isPromoActive: Bool {
            return Date() < Self.promoEndDate
        }

        // ✅ 2. ПРОМЕНИ GETTER-А НА subscriptionStatus
        var subscriptionStatus: SubscriptionStatus {
            get {
                return .removeAds
                // Взимаме реалния статус от базата/покупките
                let realStatus = SubscriptionStatus(rawValue: subscriptionStatusRaw) ?? .base
                
                // Ако потребителят вече си е платил за Advanced или Premium, не го "понижаваме" до Remove Ads.
                if realStatus == .advance || realStatus == .premium {
                    return realStatus
                }
                
                // Ако е на Base план, но промоцията е активна -> даваме му Remove Ads безплатно
                if isPromoActive {
                    return .removeAds
                }
                
                return realStatus
            }
            set {
                subscriptionStatusRaw = newValue.rawValue
                objectWillChange.send()
            }
        }

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = [] {
        didSet { updateSubscriptionStatus() }
    }
    @Published var expirationDates: [String: Date] = [:]
    @Published var isLoading = false

    private var updatesTask: Task<Void, Never>?
    var hasActiveSubscription: Bool { !purchasedProductIDs.isEmpty }

    static let shared = SubscriptionManager()
    private init() {
        Task {
            await loadProducts()
            await updatePurchasedStatus()
        }
        startListeningForUpdates()
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products
    @MainActor
    func loadProducts() async {
        if isLoading {
            print("🟦 [StoreKit] loadProducts() called while already loading – ignoring")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let ids: [String] = [
            "Wise.Eating.Remove.Ads.Monthly.v2",
            "Wise.Eating.Remove.Ads.Yearly.v2",
            "Wise.Eating.Advanced.Monthly.v2",
            "Wise.Eating.Advanced.Yearly.v2",
            "Wise.Eating.Premium.Monthly.v2",
            "Wise.Eating.Premium.Yearly.v2"
        ]

        print("🟦 [StoreKit] loadProducts() starting. IDs =\n   \(ids.joined(separator: ", "))")

        do {
            print("🟦 [StoreKit] calling Product.products(for:)")
            let fetched: [Product]

            do {
                fetched = try await Product.products(for: ids)
                print("🟩 [StoreKit] Product.products(for:) finished normally, count = \(fetched.count)")
            } catch {
                print("🟥 [StoreKit] Product.products(for:) threw error: \(error)")
                throw error
            }

            for product in fetched {
                print("   → id=\(product.id), name=\(product.displayName)")
            }

            self.products = ids.compactMap { id in
                fetched.first(where: { $0.id == id })
            }

            print("🟩 [StoreKit] products array now contains \(self.products.count) products (ordered)")
        } catch {
            print("🟥 [StoreKit] loadProducts() FAILED with error: \(error)")
        }
    }


    // MARK: - Purchase
    func canPurchase(_ newProduct: Product) -> Bool {
        guard hasActiveSubscription else { return true }
        if purchasedProductIDs.contains(newProduct.id) { return true }
        return isUpgradeable(to: newProduct)
    }

    private func isUpgradeable(to newProduct: Product) -> Bool {
        guard let currentID = purchasedProductIDs.first,
              let current = products.first(where: { $0.id == currentID }),
              let curUnit = current.subscription?.subscriptionPeriod.unit,
              let newUnit = newProduct.subscription?.subscriptionPeriod.unit
        else { return false }

        let currentIsAdvanced = currentID.lowercased().contains("advanced")
        let newIsPremium = newProduct.id.lowercased().contains("premium")
        
        let currentIsRemoveAds = currentID.lowercased().contains("remove.ads")
        let newIsAdvancedOrPremium = newProduct.id.lowercased().contains("advanced") || newIsPremium
        
        // Allow upgrade from Remove Ads to Advanced/Premium or from Advanced to Premium
        if (currentIsRemoveAds && newIsAdvancedOrPremium) || (currentIsAdvanced && newIsPremium) {
            return curUnit == newUnit
        }

        return false
    }

    func purchase(_ product: Product) async {
        if hasActiveSubscription && !isUpgradeable(to: product) && !purchasedProductIDs.contains(product.id) {
            print("Cannot purchase – already have non-upgradeable subscription.")
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await MainActor.run { register(transaction: transaction) }
                await transaction.finish()
                await updatePurchasedStatus()
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    // MARK: - Updates listener
    private func startListeningForUpdates() {
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await verification in StoreTransaction.updates {
                do {
                    let tx = try await self.checkVerified(verification)
                    await MainActor.run { self.register(transaction: tx) }
                    await tx.finish()
                    await self.updatePurchasedStatus()
                } catch {
                    print("Update verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Entitlements
    func updatePurchasedStatus() async {
        var activeIDs = Set<String>()
        var expiryDates = [String: Date]()

        for await verification in StoreTransaction.currentEntitlements {
            do {
                let tx = try checkVerified(verification)
                if tx.revocationDate == nil, let expiry = tx.expirationDate, expiry > Date() {
                    activeIDs.insert(tx.productID)
                    expiryDates[tx.productID] = expiry
                }
            } catch {
                print("Entitlement verification failed: \(error)")
            }
        }

        // Tier logic: Keep only the highest tier
        if activeIDs.contains(where: { $0.contains("Premium") }) {
            activeIDs = activeIDs.filter { $0.contains("Premium") }
        } else if activeIDs.contains(where: { $0.contains("Advanced") }) {
            activeIDs = activeIDs.filter { $0.contains("Advanced") }
        }
        
        expiryDates = expiryDates.filter { activeIDs.contains($0.key) }

        await MainActor.run {
            self.purchasedProductIDs = activeIDs
            self.expirationDates = expiryDates
        }
    }

    private func register(transaction: StoreTransaction) {
        guard transaction.revocationDate == nil else { return }
        guard products.contains(where: { $0.id == transaction.productID }) else { return }
        purchasedProductIDs.insert(transaction.productID)
        if let expiry = transaction.expirationDate {
            expirationDates[transaction.productID] = expiry
        }
    }

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }
    
    var sortedProducts: [Product] {
        products.sorted {
            guard let u1 = $0.subscription?.subscriptionPeriod.unit,
                  let u2 = $1.subscription?.subscriptionPeriod.unit else { return false }
            return u1.sortIndex < u2.sortIndex
        }
    }

    private func updateSubscriptionStatus() {
          guard !purchasedProductIDs.isEmpty else {
              subscriptionStatus = .base
              print("💎 [SubscriptionManager] Status updated: BASE (No active purchases)")
              return
          }
          
          if purchasedProductIDs.contains(where: { $0.lowercased().contains("premium") }) {
              subscriptionStatus = .premium
              print("💎 [SubscriptionManager] Status updated: PREMIUM")
          } else if purchasedProductIDs.contains(where: { $0.lowercased().contains("advanced") }) {
              subscriptionStatus = .advance
              print("💎 [SubscriptionManager] Status updated: ADVANCED")
          } else if purchasedProductIDs.contains(where: { $0.lowercased().contains("remove.ads") }) {
              subscriptionStatus = .removeAds
              print("💎 [SubscriptionManager] Status updated: REMOVE ADS")
          } else {
              subscriptionStatus = .base
              print("💎 [SubscriptionManager] Status updated: BASE (Fallback)")
          }
      }
    
    @MainActor
        func openManageSubscriptions() async {
            #if targetEnvironment(macCatalyst)
            // 🖥️ Mac Catalyst: Системният прозорец често не сработва коректно.
            // Отваряме директния линк към управление на абонаменти в App Store/System Settings.
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
            #else
            // 📱 iOS/iPadOS: Използваме native StoreKit API
            guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }

            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
                await updatePurchasedStatus()
            } catch {
                print("Failed to show subscription management: \(error)")
            }
            #endif
        }

    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedStatus()
            await MainActor.run {
                if hasActiveSubscription {
                    restorationAlertMessage = "Your previous purchases have been successfully restored."
                } else {
                    restorationAlertMessage = "No active subscriptions found to restore."
                }
            }
        } catch {
            await MainActor.run {
                restorationAlertMessage = "Failed to restore purchases. Please try again later. (\(error.localizedDescription))"
            }
        }
    }
    
    var maxProfilesAllowed: Int {
          switch subscriptionStatus {
          case .base, .removeAds:
              return 2
          case .advance:
              return 4
          case .premium:
              return 12
          }
      }

      var nextTierForProfileLimit: SubscriptionCategory? {
          switch subscriptionStatus {
          case .base, .removeAds:
              return .advance
          case .advance:
              return .premium
          case .premium:
              return nil
          }
      }

      func activeProfileIDs(from profiles: [Profile]) -> Set<UUID> {
          guard !profiles.isEmpty else { return [] }

          let sorted = profiles.sorted { lhs, rhs in
              if lhs.createdAt == rhs.createdAt {
                  return lhs.updatedAt < rhs.updatedAt
              }
              return lhs.createdAt < rhs.createdAt
          }

          switch subscriptionStatus {
          case .premium:
              let maxCount = 12
              return Set(sorted.prefix(maxCount).map { $0.id })

          case .advance:
              let maxCount = 4
              return Set(sorted.prefix(maxCount).map { $0.id })

          case .base, .removeAds:
              var adultTaken = false   // без възрастово ограничение
              var childTaken = false   // до 14 г.
              var active: [UUID] = []

              for profile in sorted {
                  let isChild = profile.age <= 14

                  if isChild {
                      if !childTaken {
                          childTaken = true
                          active.append(profile.id)
                      }
                  } else {
                      if !adultTaken {
                          adultTaken = true
                          active.append(profile.id)
                      }
                  }

                  if adultTaken && childTaken {
                      break
                  }
              }

              return Set(active)
          }
      }
}

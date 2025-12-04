import SwiftUI
import StoreKit
import SafariServices
// Helper to show Safari inside the app
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct SubscriptionListView: View {
    let title: String
    let products: [Product]
    @Binding var selectedProductID: String?
    @StateObject private var manager = SubscriptionManager.shared
    @State private var presentedURL: URL?
    
    // Добавяме EffectManager
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            // ПРОМЯНА: Добавяме padding към основния VStack
            VStack(spacing: 20) {
                // Show the corresponding feature view based on the title
                if title == "Ads" {
                    RemoveAdsSubscriptionView()
                } else if title == "Advanced" {
                    AdvancedSubscriptionView()
                } else if title == "Premium" {
                    PremiumSubscriptionView()
                }
                
                // ПРОМЯНА: Картите с продукти вече са в отделна секция
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(products) { product in
                            let isActive = manager.purchasedProductIDs.contains(product.id)
                            let isSelectedOrActive = isActive || product.id == selectedProductID
                            let canBuy = manager.canPurchase(product)
                            
                            SubscriptionCard(
                                product: product,
                                isActive: isActive,
                                isSelected: isSelectedOrActive,
                                expirationDate: manager.expirationDates[product.id]
                            ) {
                                if canBuy {
                                    selectedProductID = product.id
                                }
                            }
                            .disabled(!canBuy)
                            .opacity(!canBuy ? 0.6 : 1.0)
                        }
                    }
                    
                    ActiveSubscriptionStatusView()
                    
                    if let id = selectedProductID,
                       let product = manager.products.first(where: { $0.id == id }),
                       !manager.purchasedProductIDs.contains(id),
                       manager.canPurchase(product) {
                        PurchaseSectionView(selectedProductID: id)
                    }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20) // Прилагаме стил
                
                // ПРОМЯНА: Линковете също са в отделна секция
                VStack(spacing: 16) {
                    HStack {
                        Button { Task { await manager.openManageSubscriptions() } } label: {
                            Label("Manage Subscription", systemImage: "creditcard")
                        }
                        .font(.footnote)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        
                        Spacer()
                        
                        Button { Task { await manager.restorePurchases() } } label: {
                            Label("Restore Purchases", systemImage: "arrow.trianglehead.2.clockwise")
                        }
                        .font(.footnote)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)

                    }
                    HStack {
                        Button { presentedURL = URL(string: "https://www.wise-eating.com/privacy")! } label: {
                            Label("Privacy Policy", systemImage: "lock.shield")
                        }
                        .font(.footnote)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)

                        Spacer()
                        
                        Button {
                            presentedURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                        } label: {
                            Label("Terms of Use (EULA)", systemImage: "doc.text")
                        }
                        .font(.footnote)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)


                    }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20) // Прилагаме стила
            }
            .padding(.top, 10)
            .padding(.horizontal) // Padding за целия ScrollView
            .sheet(item: $presentedURL) { url in
                SafariView(url: url)
            }
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
    }
    
    @ViewBuilder
    private func ActiveSubscriptionStatusView() -> some View {
        if let activeID = manager.purchasedProductIDs.first,
           let product = manager.products.first(where: { $0.id == activeID }),
           let expiry = manager.expirationDates[activeID] {
            
            let planType = manager.subscriptionStatus.title
            let period = product.periodUnitOnly
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Your current plan is \(planType) \(period)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Text("Renews on \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 10)
        }
    }
    
    @ViewBuilder
    private func PurchaseSectionView(selectedProductID: String?) -> some View {
        if let id = selectedProductID,
           let product = manager.products.first(where: { $0.id == id }) {
            
            VStack(spacing: 15) {
                Button {
                    Task { await manager.purchase(product) }
                } label: {
                    let label = product.subscription?.introductoryOffer != nil ? "Start Free Trial" : "Subscribe Now"
                    Text(label)
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(effectManager.isLightRowTextColor ? .black : .white)
                        .background(effectManager.currentGlobalAccentColor)
                        .cornerRadius(10)
                }

                // ✅ Инфо за абонамента – title, length, price, auto-renew
                if let subscription = product.subscription {
                    let period = subscription.subscriptionPeriod
                    let periodDescription: String = {
                        switch period.unit {
                        case .day:   return period.value == 1 ? "daily"   : "every \(period.value) days"
                        case .week:  return period.value == 1 ? "weekly"  : "every \(period.value) weeks"
                        case .month: return period.value == 1 ? "monthly" : "every \(period.value) months"
                        case .year:  return period.value == 1 ? "yearly"  : "every \(period.value) years"
                        @unknown default: return "recurring"
                        }
                    }()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(product.displayName) – \(periodDescription) subscription.")
                        Text("Price: \(product.displayPrice). The subscription renews automatically unless cancelled at least 24 hours before the end of the current period.")
                        Text("Payment will be charged to your Apple ID account. You can manage or cancel your subscription in Settings > Apple ID > Subscriptions.")
                        Text("You can also manage or cancel your subscription using the “Manage Subscription” button below.")
                    }
                    .font(.footnote)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            }
            .padding(.vertical)
        }
    }

}

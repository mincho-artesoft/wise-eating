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
    
    @ObservedObject private var effectManager = EffectManager.shared

    private var privacyPolicyURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "AyurvedaAsanaYogaPrivacyPolicyURL") as? String,
            !value.isEmpty
        else {
            return nil
        }
        return URL(string: value)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 1. Feature Info Views
                if title == "Ads" {
                    RemoveAdsSubscriptionView()
                } else if title == "Advanced" {
                    AdvancedSubscriptionView()
                } else if title == "Premium" {
                    PremiumSubscriptionView()
                }
                
                // 2. Subscription Cards Section
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
                .glassCardStyle(cornerRadius: 20)
                
                // 3. Links Section
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
                        if let privacyPolicyURL {
                            Button {
                                openLink(privacyPolicyURL)
                            } label: {
                                Label("Privacy Policy", systemImage: "lock.shield")
                            }
                            .font(.footnote)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)

                            Spacer()
                        }
                        
                        Button {
                            openLink(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        } label: {
                            Label("Terms of Use (EULA)", systemImage: "doc.text")
                        }
                        .font(.footnote)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
            }
            .padding(.top, 10)
            .padding(.horizontal)
            // Sheet-ът се активира само ако presentedURL не е nil (т.е. само на iOS)
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
    
    // Помощна функция за отваряне на линкове
    private func openLink(_ url: URL) {
        presentedURL = url
    }
    
    // ... (ActiveSubscriptionStatusView и PurchaseSectionView остават същите като в твоя код)
    
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
                        Text("Payment will be charged to your Apple ID account.")
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

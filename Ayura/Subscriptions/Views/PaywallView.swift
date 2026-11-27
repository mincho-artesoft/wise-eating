import StoreKit
import SwiftUI

/// The plan screen behind `FeatureFlags.newPaywall`: one recommended plan
/// (no ads), a yearly/monthly switch, and the other plans one tap away in the
/// earlier `SubscriptionView`.
struct PaywallView: View {
    /// Shown as a sheet (with a close button) or inside the Plans tab.
    let isSheet: Bool
    let onSeeAllPlans: () -> Void
    var onClose: () -> Void = {}

    @StateObject private var manager = SubscriptionManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var yearly = true
    @State private var presentedURL: URL?
    @State private var restoreMessage: String?

    private let privacyPolicyURL = URL(string: "https://www.ayurveda-asana-yoga.wise-eating.com/privacy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private var accent: Color { effectManager.currentGlobalAccentColor }
    private var monthlyProduct: Product? { manager.products.first { $0.id == SubscriptionProductID.noAds } }
    private var yearlyProduct: Product? { manager.products.first { $0.id == SubscriptionProductID.noAdsYearly } }
    private var selectedProduct: Product? { yearly ? (yearlyProduct ?? monthlyProduct) : (monthlyProduct ?? yearlyProduct) }

    /// Whole per cent saved by a year against twelve months, when both prices are known.
    private var yearlySaving: Int? {
        guard let monthlyProduct, let yearlyProduct, monthlyProduct.price > 0 else { return nil }
        let twelveMonths = monthlyProduct.price * 12
        let saved = (twelveMonths - yearlyProduct.price) / twelveMonths * 100
        // NSDecimalNumber.intValue is wrong for long fractions; go through Double.
        let percent = Int(NSDecimalNumber(decimal: saved).doubleValue.rounded(.down))
        return percent > 0 ? percent : nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if isSheet {
                    HStack {
                        Spacer()
                        Button(String(localized: "Not now"), action: onClose)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .glassCardStyle(cornerRadius: 18)
                            .accessibilityIdentifier("paywall-close")
                    }
                }

                VStack(spacing: 8) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 54))
                        .symbolRenderingMode(.hierarchical)
                    Text("Keep the app calm")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Everything in the app is free to use. A plan removes the ads and supports the work.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                }

                VStack(alignment: .leading, spacing: 12) {
                    benefit("nosign", String(localized: "No ads anywhere in the app"))
                    benefit("person.2", String(localized: "More profiles for a family with the larger plans"))
                    benefit("arrow.uturn.backward", String(localized: "Cancel at any time in your Apple Account"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassCardStyle(cornerRadius: 20)

                if manager.hasActiveSubscription {
                    activePlan
                } else if selectedProduct != nil {
                    offer
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading prices…").font(.footnote).opacity(0.7)
                    }
                    .padding(.vertical, 24)
                }

                Button(String(localized: "See all plans"), action: onSeeAllPlans)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("paywall-all-plans")

                links
                Spacer(minLength: isSheet ? 20 : 150)
            }
            .padding(.horizontal)
            .padding(.top, isSheet ? 16 : 10)
            .foregroundStyle(accent)
        }
        .background { if isSheet { ThemeBackgroundView().ignoresSafeArea() } }
        .task { if manager.products.isEmpty { await manager.loadProducts() } }
        .sheet(item: $presentedURL) { SafariView(url: $0) }
        .onChange(of: manager.restorationAlertMessage) { _, message in
            restoreMessage = message
        }
        .alert(String(localized: "Restore Purchases"), isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil; manager.restorationAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .onChange(of: manager.hasActiveSubscription) { _, active in
            if active, isSheet { onClose() }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            Text(text).font(.subheadline)
        }
    }

    private var offer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                periodButton(title: String(localized: "Yearly"), product: yearlyProduct, isOn: yearly) { yearly = true }
                periodButton(title: String(localized: "Monthly"), product: monthlyProduct, isOn: !yearly) { yearly = false }
            }

            if yearly, let yearlySaving {
                Text("Save \(yearlySaving)% vs monthly")
                    .font(.footnote.weight(.semibold))
            }

            if let product = selectedProduct {
                Button {
                    Task { await manager.purchase(product) }
                } label: {
                    Text(manager.eligibleTrialIDs.contains(product.id)
                         ? String(localized: "Start Free Trial")
                         : String(localized: "Continue"))
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(effectManager.isLightRowTextColor ? .black : .white)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("paywall-purchase")

                Text("\(product.displayPrice) \(yearly ? String(localized: "per year") : String(localized: "per month")). Renews automatically until cancelled; cancel at least 24 hours before the period ends. Payment is charged to your Apple Account.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 20)
    }

    private func periodButton(title: String, product: Product?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(product?.displayPrice ?? "—").font(.title3.weight(.bold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .glassCardStyle(cornerRadius: 14)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent, lineWidth: isOn ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(product == nil)
        .opacity(product == nil ? 0.5 : 1)
    }

    private var activePlan: some View {
        VStack(spacing: 6) {
            Text("Subscription access is active")
                .font(.headline)
            Text("Your current plan: \(manager.subscriptionStatus.title)")
                .font(.subheadline)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassCardStyle(cornerRadius: 20)
    }

    private var links: some View {
        HStack(spacing: 18) {
            Button(String(localized: "Restore Purchases")) { Task { await manager.restorePurchases() } }
            Button(String(localized: "Privacy Policy")) { presentedURL = privacyPolicyURL }
            Button(String(localized: "Terms of Use (EULA)")) { presentedURL = termsURL }
        }
        .font(.caption)
        .opacity(0.8)
    }
}

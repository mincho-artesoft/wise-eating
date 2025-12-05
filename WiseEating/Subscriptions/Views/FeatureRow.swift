import SwiftUI

// Shared helper for bullet-list
struct FeatureRow: View {
    let feature: String
    @ObservedObject private var effectManager = EffectManager.shared // Добавяме EffectManager

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                // ПРОМЯНА: Използваме цвят от темата
                .foregroundColor(effectManager.currentGlobalAccentColor)
            Text(feature)
                .font(.subheadline)
                // ПРОМЯНА: Използваме цвят от темата
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Remove Ads Subscription View
struct RemoveAdsSubscriptionView: View {
    @ObservedObject private var effectManager = EffectManager.shared // Добавяме EffectManager

    var body: some View {
        // ПРОМЯНА: Обвиваме в VStack и прилагаме стил
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove Ads Plan")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(feature: "All Base Plan features")
                FeatureRow(feature: "Enjoy an ad-free experience")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCardStyle(cornerRadius: 20) // Прилагаме стила
    }
}


// MARK: - Advanced Subscription View
struct AdvancedSubscriptionView: View {
    @ObservedObject private var effectManager = EffectManager.shared // Добавяме EffectManager

    var body: some View {
        // ПРОМЯНА: Обвиваме в VStack и прилагаме стил
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Plan")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(feature: "All Remove Ads Plan features")
                FeatureRow(feature: "Up to 4 profiles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCardStyle(cornerRadius: 20) // Прилагаме стила
    }
}

// MARK: - Premium Subscription View
struct PremiumSubscriptionView: View {
    @ObservedObject private var effectManager = EffectManager.shared // Добавяме EffectManager

    var body: some View {
        // ПРОМЯНА: Обвиваме в VStack и прилагаме стил
        VStack(alignment: .leading, spacing: 16) {
            Text("Premium Plan")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(feature: "All Advanced Plan features")
                FeatureRow(feature: "Up to 12 profiles")

            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCardStyle(cornerRadius: 20) // Прилагаме стила
    }
}

// MARK: - Base (Free) Subscription View
struct BaseSubscriptionView: View {
    @ObservedObject private var effectManager = EffectManager.shared // Добавяме EffectManager

    var body: some View {
        // ПРОМЯНА: Обвиваме в VStack и прилагаме стил
        VStack(alignment: .leading, spacing: 16) {
            Text("Base Plan")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(feature: "1 Main Profile")
                FeatureRow(feature: "1 Child Profile (up to 4 years)")
                FeatureRow(feature: "Meal Tracking")
                FeatureRow(feature: "Workout Tracking")
                FeatureRow(feature: "Storage List")
                FeatureRow(feature: "Shopping List")
                FeatureRow(feature: "AI generation of meal plans, treaning plans, and more")
                FeatureRow(feature: "Analytics Views")
                FeatureRow(feature: "Notes")
                FeatureRow(feature: "and more")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCardStyle(cornerRadius: 20) // Прилагаме стила
    }
}

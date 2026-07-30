import SwiftUI
import StoreKit

struct SubscriptionCard: View {
    let product: Product
    let isActive: Bool
    let isSelected: Bool
    let expirationDate: Date?
    let action: () -> Void
    
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(product.periodUnitOnly)
                        .font(.headline)
                    Text(product.displayPrice)
                        .font(.title2.weight(.semibold))
                    
                    if let monthly = product.pricePerMonth,
                       product.subscription?.subscriptionPeriod.unit == .year {
                        Text("Equivalent to \(monthly) per month")
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }

                    if !isActive, let intro = product.subscription?.introductoryOffer {
                        let plural = intro.period.value > 1
                        let unit = intro.period.unit.noun(plural: plural).lowercased()
                        Text("\(intro.period.value) \(unit) free")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(isSelected ? effectManager.currentGlobalAccentColor : Color(.systemGray3))
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isActive ? Color.green : (isSelected ? effectManager.currentGlobalAccentColor : Color.clear),
                        lineWidth: isSelected || isActive ? 2.5 : 0
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            .contentShape(Rectangle())   // 👈 ВАЖНОТО
        }
        .buttonStyle(.plain)
    }
}

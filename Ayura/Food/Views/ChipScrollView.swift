import SwiftUI

struct ChipScrollView<T: Identifiable & Hashable>: View {
    let title: String
    let items: [T]
    let textColor: Color
    var isAlertSection: Bool = false
    
    init(title: String, items: [T], textColor: Color, isAlertSection: Bool = false) {
        self.title = title
        self.items = items.isEmpty ? [] : items
        self.textColor = textColor
        self.isAlertSection = isAlertSection
    }
    
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(textColor.opacity(0.8))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if T.self == DisplayableNutrient.self {
                            ForEach(items as! [DisplayableNutrient]) { nutrient in
                                GlassChipView(label: nutrient.name, value: formatted(nutrient.value, unit: nutrient.unit), textColor: textColor)
                            }
                        } else if T.self == Allergen.self {
                            ForEach(items as! [Allergen]) { allergen in
                                GlassChipView(label: allergen.rawValue, isAlert: true, textColor: isAlertSection ? .orange : textColor)
                            }
                        } else if T.self == MuscleGroup.self {
                            ForEach(items as! [MuscleGroup]) { group in
                                GlassChipView(label: group.rawValue, color: .purple, textColor: textColor)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func formatted(_ value: Double, unit: String) -> String {
        let (scaled, newUnit) = autoScale(value, unit: unit)
        let str: String
        if scaled.truncatingRemainder(dividingBy: 1) == 0 { str = String(format: "%.0f", scaled) }
        else { str = String(format: "%.1f", scaled) }
        return "\(str) \(newUnit)"
    }

    private func autoScale(_ value: Double, unit: String) -> (Double, String) {
        var v = value, u = unit.lowercased()
        while v >= 1000 {
            switch u {
            case "ng": v /= 1000; u = "µg"; case "µg", "mcg": v /= 1000; u = "mg"; case "mg": v /= 1000; u = "g"; default: return (v, unit)
            }
        }
        return (v, u == unit.lowercased() ? unit : u)
    }
}

enum GlassChipIconPlacement {
    case leading
    case trailing
}

struct GlassChipView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    let label: String
    var value: String? = nil
    var isAlert: Bool = false
    var color: Color? = nil
    var systemImage: String? = nil
    let textColor: Color
    var font: Font = .caption
    var fontWeight: Font.Weight = .medium
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 5
    var iconPlacement: GlassChipIconPlacement = .leading
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                chipContent
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            chipContent
        }
    }

    private var chipContent: some View {
        let resolvedTextColor = isAlert ? Color.orange : textColor
        let resolvedIconColor = isAlert
            ? Color.orange
            : (isSelected ? (color ?? textColor) : textColor)

        return HStack(spacing: 5) {
            if isAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(font)
                    .foregroundColor(.orange) // Алергиите остават оранжеви за акцент
            } else if let systemImage, iconPlacement == .leading {
                Image(systemName: systemImage)
                    .font(font)
                    .foregroundColor(resolvedIconColor)
            }
            Text(label)
                .font(font)
                .fontWeight(fontWeight)
                // Ако е alert, цветът е оранжев, иначе е подаденият textColor
                .foregroundColor(resolvedTextColor)
            
            if let valueText = value {
                Text(valueText)
                    .font(.caption)
                    // Стойността също е оранжева при alert, иначе е по-бледа версия на textColor
                    .foregroundColor(isAlert ? .orange.opacity(0.8) : textColor.opacity(0.7))
            }

            if !isAlert,
               let systemImage,
               iconPlacement == .trailing {
                Image(systemName: systemImage)
                    .font(font)
                    .foregroundColor(resolvedIconColor)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            if isSelected {
                Capsule()
                    .fill((color ?? textColor).opacity(0.18))
            }
        }
        .glassCardStyle(cornerRadius: 25)
        .clipShape(Capsule())
        .overlay {
            if isSelected {
                Capsule()
                    .stroke((color ?? textColor).opacity(0.65), lineWidth: 2)
            }
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

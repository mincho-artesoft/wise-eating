import SwiftUI
import UIKit
import CoreText

struct SearchResultRow: View {
    let item: FoodItem
    @ObservedObject var smartSearch: SmartFoodSearch3
    @ObservedObject private var effectManager = EffectManager.shared
    let onTap: () -> Void

    private let phOpacity: Double = 0.1
    private let titleFont: UIFont = .preferredFont(forTextStyle: .body)

    @State private var titleFirstPart: String = ""
    @State private var titleSecondPart: String? = nil
    @State private var titleRestPart: String? = nil
    
    // New state to measure the badge width dynamically
    @State private var badgeWidth: CGFloat = 0
    // State to track the available width for text content
    @State private var contentWidth: CGFloat = 0

    private enum IconKind {
        case favorite
        case recipe
        case menu
    }

    private var iconKinds: [IconKind] {
        var kinds: [IconKind] = []
        if item.isFavorite { kinds.append(.favorite) }
        if item.isRecipe  { kinds.append(.recipe) }
        if item.isMenu    { kinds.append(.menu) }
        return kinds
    }

    private var iconCount: Int {
        iconKinds.count
    }

    var body: some View {
            Button(action: onTap) {
                // 1. Променяме spacing на 0, за да имаме пълен контрол
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Main Upper Section
                    HStack(alignment: .top, spacing: 12) {
                        
                        // --- LEFT COLUMN: Thumbnail & icons ---
                        VStack(spacing: 4) {
                            if let thumbnail = item.foodImage(variant: "144") {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(effectManager.currentGlobalAccentColor.opacity(0.15))

                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 20))
                                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                                }
                                .frame(width: 40, height: 40)
                            }
                            iconsView
                        }

                        // --- RIGHT COLUMN: Text & Badges ---
                        VStack(alignment: .leading, spacing: 0) {
                            
                            // 1. Top Row: First Part
                            HStack(alignment: .top, spacing: 0) {
                                Text(titleFirstPart.isEmpty ? item.name : titleFirstPart)
                                    .font(.body)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer(minLength: 0)
                                
                                // Badges
                                VStack(alignment: .trailing, spacing: 4) {
                                    if item.minAgeMonths >= 0 {
                                        let ageText = item.minAgeMonths <= 48
                                        ? "\(item.minAgeMonths)m+"
                                        : "\(item.minAgeMonths / 12)y+"
                                        
                                        Text(ageText)
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.8))
                                            .clipShape(Capsule())
                                    }

                                    Text("per 100 g")
                                        .font(.caption)
                                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .onAppear { badgeWidth = proxy.size.width }
                                            .onChange(of: proxy.size.width) { badgeWidth = $0 }
                                    }
                                )
                            }

                            // 2. Middle Row: Second Part
                            if let second = titleSecondPart, !second.isEmpty {
                                Text(second)
                                    .font(.body)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                                    // Добавяме малък фиксиран отстъп, ако е необходимо
                                    .padding(.top, 1)
                            }
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        contentWidth = geo.size.width
                                        calculateSplit()
                                    }
                                    .onChange(of: geo.size.width) { newWidth in
                                        contentWidth = newWidth
                                        calculateSplit()
                                    }
                                    .onChange(of: badgeWidth) { _ in
                                        calculateSplit()
                                    }
                            }
                        )
                    }

                    // 3. Bottom Row: Rest Part
                    // Тъй като главният VStack е с spacing: 0, този текст ще залепне за горния
                    if let rest = titleRestPart, !rest.isEmpty {
                        Text(rest)
                            .font(.body)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .multilineTextAlignment(.leading)
                            // Тук премахваме логиката с iconCount и слагаме фиксирана стойност,
                            // която съвпада с разстоянието между редовете на шрифта ви (прибл. 0-2)
                            .padding(.top, 1)
                    }

                    // Tags (pH, Allergens, Diets)
                    // Тук добавяме padding, защото премахнахме spacing: 8 от главния контейнер
                    VStack(alignment: .leading, spacing: 4) {
                        if smartSearch.searchContext.isPhActive && item.ph > 0 {
                            Text("pH: \(String(format: "%.1f", item.ph))")
                                .font(.caption2)
                                .padding(4)
                                .cornerRadius(4)
                                .foregroundColor(phColor(item.ph))
                        }

                        if let allergens = item.allergens, !allergens.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                Text(allergens.map { $0.name }.joined(separator: ", "))
                                    .font(.caption2)
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundColor(.orange)
                        }

                        if let diets = item.diets, !diets.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "leaf.circle.fill")
                                    .font(.caption2)
                                Text(diets.map { $0.name }.joined(separator: ", "))
                                    .font(.caption2)
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.top, 8) // Връщаме визуалното разстояние преди таговете

                    // Nutrients row
                    nutrientsView
                        .padding(.top, 8) // Връщаме визуалното разстояние преди нутриентите
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    
    @ViewBuilder
        private var nutrientsView: some View {
            if !smartSearch.searchContext.displayNutrients.isEmpty {
                let activeNutrients = smartSearch.searchContext.displayNutrients.compactMap { nutrient -> (String, String, String)? in
                    if let result = smartSearch.normalizedAndScaledValue(for: item, nutrient: nutrient) {
                        return (smartSearch.displayName(for: nutrient), String(format: "%.1f", result.value), result.unit)
                    }
                    return nil
                }

                if !activeNutrients.isEmpty {
                    activeNutrients.reduce(Text("")) { (accumulatedText, details) in
                        let (name, value, unit) = details
                        
                        // КОРЕКЦИЯ: Заменяме интервалите вътре в самото име (напр. "Vit C" -> "Vit\u{00A0}C")
                        // Така "Vit" никога няма да се отдели от "C".
                        let safeName = name.replacingOccurrences(of: " ", with: "\u{00A0}")
                        
                        let segment =
                            Text(safeName + ":\u{00A0}") // Име (свързано) + двоеточие + непрекъсваем интервал
                                .font(.caption)
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                            + Text("\(value)\u{00A0}\(unit)") // Стойност + непрекъсваем интервал + единица
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            + Text("    ") // Тук оставяме нормален интервал, за да може да се пренася САМО МЕЖДУ различните нутриенти
                        
                        return accumulatedText + segment
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                
            } else {
                // Fallback за макроси (без промяна)
                HStack(spacing: 8) {
                    if let calories = smartSearch.normalizedAndScaledValue(for: item, nutrient: .energy) {
                        let central: CGFloat = 60
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: central * 0.2))
                                .foregroundColor(.orange)
                            Text(String(format: "%.0f", calories.value))
                                .font(.system(size: central * 0.24, weight: .bold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                            Text("kcal")
                                .font(.system(size: central * 0.18))
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
                    }
                    macroText(for: .protein, label: "Prot")
                    macroText(for: .totalFat, label: "Fat")
                    macroText(for: .carbs, label: "Carb")
                }
            }
        }
    
    @ViewBuilder
    private func macroText(for nutrient: NutrientType, label: String) -> some View {
        if let val = smartSearch.normalizedAndScaledValue(for: item, nutrient: nutrient) {
            let valInGrams: Double = {
                switch val.unit.lowercased() {
                case "mg": return val.value / 1000.0
                case "µg", "mcg": return val.value / 1_000_000.0
                case "kg": return val.value * 1000.0
                default: return val.value
                }
            }()
            
            HStack(spacing: 2) {
                Text("\(label):")
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                Text("\(String(format: "%.1f", valInGrams)) g")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
        }
    }

    @ViewBuilder
    private var iconsView: some View {
        switch iconKinds.count {
        case 0: EmptyView()
        case 1, 2:
            HStack(spacing: 2) {
                ForEach(Array(iconKinds.enumerated()), id: \.offset) { _, kind in iconView(kind) }
            }
        default:
            VStack(spacing: 2) {
                HStack(spacing: 2) { iconView(iconKinds[0]); iconView(iconKinds[1]) }
                HStack(spacing: 2) { iconView(iconKinds[2]) }
            }
        }
    }

    @ViewBuilder
    private func iconView(_ kind: IconKind) -> some View {
        switch kind {
        case .favorite:
            Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption2)
        case .recipe:
            Image(systemName: "list.bullet.rectangle.portrait").foregroundColor(effectManager.currentGlobalAccentColor).font(.caption2)
        case .menu:
            Image(systemName: "list.clipboard").foregroundColor(effectManager.currentGlobalAccentColor).font(.caption2)
        }
    }
    
    private func phColor(_ ph: Double) -> Color {
        if ph < 6.5 { return .red }
        if ph > 7.5 { return .blue }
        return .green
    }
    
    // --- UPDATED LOGIC ---
    
    @MainActor
    private func calculateSplit() {
        // Only calculate if we have valid dimensions
        guard contentWidth > 0 else { return }
        
        // Width for the top lines (constrained by badges)
        // We add a little buffer (8 points) to ensure text doesn't touch the badge
        let availableTopWidth = max(0, contentWidth - badgeWidth - 8)
        
        // Width for the second part (fills the space)
        let availableBottomWidth = contentWidth

        let result = TextSplitterCore.split3(
            text: item.name,
            font: titleFont,
            topWidth: availableTopWidth,
            bottomWidth: availableBottomWidth
        )

        // Logic to assign parts based on icon presence
        if iconCount > 0 {
            // With icons: We keep the distinction between First (top narrow) and Second (bottom wide)
            if result.first != titleFirstPart ||
               result.second != titleSecondPart ||
               result.rest != titleRestPart {
                titleFirstPart = result.first
                titleSecondPart = result.second
                titleRestPart = result.rest
            }
        } else {
            // Without icons: We merge the 'second' part into the 'rest' part
            // because visually everything after the top 2 lines drops below the thumbnail anyway.
            let combinedTail: String? = {
                if let second = result.second, let rest = result.rest {
                    return second + rest
                } else if let second = result.second {
                    return second
                } else {
                    return result.rest
                }
            }()

            if result.first != titleFirstPart ||
               combinedTail != titleRestPart ||
               titleSecondPart != nil {
                titleFirstPart = result.first
                titleSecondPart = nil
                titleRestPart = combinedTail
            }
        }
    }
}

fileprivate enum TextSplitterCore {
    /// Split text into up to three segments using variable widths:
    ///  - first: up to 2 lines using `topWidth`
    ///  - second: 1 line using `bottomWidth`
    ///  - rest: remaining text
    static func split3(
        text: String,
        font: UIFont,
        topWidth: CGFloat,
        bottomWidth: CGFloat
    ) -> (first: String, second: String?, rest: String?) {
        guard !text.isEmpty, topWidth > 0 else {
            return (text, nil, nil)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let fullAttr = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(fullAttr)

        let utf16Count = fullAttr.length
        var currentIndex: CFIndex = 0
        var lineEndIndices: [CFIndex] = []

        // We want:
        // Line 1: Uses topWidth
        // Line 2: Uses topWidth
        // Line 3: Uses bottomWidth
        
        var lineIndex = 0
        
        // 1. Calculate lines based on specific widths
        while currentIndex < utf16Count {
            // Determine width based on line number (0 and 1 are top, 2 is bottom)
            let widthToUse = (lineIndex < 2) ? topWidth : bottomWidth
            
            let count = CTTypesetterSuggestLineBreak(typesetter, currentIndex, Double(widthToUse))
            if count <= 0 { break }
            
            currentIndex += count
            lineEndIndices.append(currentIndex)
            
            lineIndex += 1
            // We only care about explicitly splitting the first 3 lines.
            // Everything after line 3 falls into "rest".
            if lineIndex >= 3 { break }
        }

        // --- Helper to convert Offset to Index ---
        func index(forUTF16Offset offset: Int) -> String.Index {
            String.Index(utf16Offset: offset, in: text)
        }

        // --- PART 1: First 2 Lines ---
        // If we have fewer than 1 line of break points, the whole text fits in first part.
        if lineEndIndices.isEmpty {
             return (text, nil, nil)
        }
        
        // The end of "first part" is the end of line 2 (index 1) or line 1 (index 0)
        let firstPartEndIndexOffset = lineEndIndices[min(1, lineEndIndices.count - 1)]
        let firstPartStringIndex = index(forUTF16Offset: Int(firstPartEndIndexOffset))
        let first = String(text[..<firstPartStringIndex])
        
        // If we ran out of text within the first 2 lines
        if Int(firstPartEndIndexOffset) >= utf16Count {
            return (first, nil, nil)
        }

        // --- PART 2: The 3rd Line (Wide) ---
        // The remaining text starts after Part 1
        let remainingAfterFirst = String(text[firstPartStringIndex...])
        
        // If we successfully calculated a 3rd line break in the loop above:
        // The end of "second part" is lineEndIndices[2] (if it exists)
        // BUT relative to the full text string.
        
        var second: String? = nil
        var rest: String? = nil
        
        if lineEndIndices.count > 2 {
            let secondPartEndIndexOffset = lineEndIndices[2]
            let secondPartStringIndex = index(forUTF16Offset: Int(secondPartEndIndexOffset))
            
            // Extract the second part (from end of first part to end of 3rd line)
            second = String(text[firstPartStringIndex..<secondPartStringIndex])
            
            // Remainder
            if Int(secondPartEndIndexOffset) < utf16Count {
                rest = String(text[secondPartStringIndex...])
            }
        } else {
            // If the loop didn't reach a 3rd line break, it means the text ended
            // exactly at line 3 or before filling line 3 fully.
            // So everything remaining is 'second'.
            if !remainingAfterFirst.isEmpty {
                second = remainingAfterFirst
            }
        }
        
        return (first, second, rest)
    }
}

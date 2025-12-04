import SwiftUI

protocol ColorSelectableItem: Identifiable, Hashable {
    var id: String { get }
    var name: String { get }
    /// Може да си остане в протокола за съвместимост, но вече не се ползва.
    var displayText: String? { get }
    var colorHex: String { get }
}

struct ColorTextMultiSelectGridView<Item: ColorSelectableItem>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Входни данни
    let items: [Item]
    @Binding var selection: Set<Item.ID>
    let searchPrompt: String

    /// Височината на реда/„плочката“. Използваме само височината; ширината е full-width.
    let itemContentSize: CGSize
    
    // MARK: - Състояние
    @State private var searchText: String = ""
    
    private var filteredItems: [Item] {
        searchText.isEmpty
        ? items
        : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // Един колона → един елемент на ред
    private let columns = [GridItem(.flexible(), spacing: 12)]
    
    var body: some View {
        VStack(spacing: 20) {
            // Търсене
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                TextField(
                    searchPrompt,
                    text: $searchText,
                    prompt: Text("Search...")
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                )
                .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .padding()
            .glassCardStyle(cornerRadius: 25)
            
            // Мрежа (всъщност 1 колона → списък от плочки)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems) { item in
                        ColorTextSelectItemView(
                            item: item,
                            isSelected: selection.contains(item.id),
                            rowHeight: itemContentSize.height // ползваме само височината
                        ) {
                            withAnimation(.spring()) {
                                if selection.contains(item.id) {
                                    selection.remove(item.id)
                                } else {
                                    selection.insert(item.id)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 4)
                Spacer(minLength: 150)
            }
        }
        .padding(.horizontal)
    }
}

/// Плочка за един ред — ползва само item.name
private struct ColorTextSelectItemView<Item: ColorSelectableItem>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let item: Item
    let isSelected: Bool
    let rowHeight: CGFloat
    let action: () -> Void

    // Регулирай, ако искаш по-силен/по-слаб фон под glass ефекта
    private let backgroundOpacity: Double = 0.18

    var body: some View {
        Button(action: action) {
            // Съдържание: само името, авто-мащабирано
            FittingLabel(
                text: item.name,
                baseFontSize: rowHeight * 0.45,
                weight: .bold,
                minScale: 0.5,
                lines: 1,
                color: effectManager.currentGlobalAccentColor   // NEW
            )
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Фон с цвета на елемента (преди glass-а)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: item.colorHex).opacity(backgroundOpacity))
            )
            // Glass стил
            .glassCardStyle(cornerRadius: 20)
            // Рамка при селекция
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// UILabel-базиран етикет, който се свива до width (едноредов).
struct FittingLabel: UIViewRepresentable {
    let text: String
    let baseFontSize: CGFloat
    let weight: UIFont.Weight
    let minScale: CGFloat
    let lines: Int
    let color: Color?            // NEW

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = minScale
        label.numberOfLines = lines
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        if let color { label.textColor = UIColor(color) }   // NEW
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = .systemFont(ofSize: baseFontSize, weight: weight)
        if let color { label.textColor = UIColor(color) }   // NEW
    }
}

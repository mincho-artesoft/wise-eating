import SwiftUI

protocol SelectableItem: Identifiable, Hashable {
    var id: String { get }
    var name: String { get }
    // An optional name for a SF Symbol or asset image.
    var iconName: String? { get }
    // A fallback for text-based icons if no image is available.
    var iconText: String? { get }
}

/// Преизползваем изглед, който показва елементи в мрежа с възможност за търсене и множествен избор,
/// с персонализирани икони.
struct IconMultiSelectGridView<Item: SelectableItem>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Входни данни
    let items: [Item]
    @Binding var selection: Set<Item.ID>
    let searchPrompt: String
    
    // НОВИ ЗАДЪЛЖИТЕЛНИ ПАРАМЕТРИ
    let iconSize: CGSize
    let useIconColor: Bool
    @State var dissableText: Bool = false
    // MARK: - Състояние
    @State private var searchText: String = ""
    
    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 20) {
            // Поле за търсене
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                TextField(searchPrompt, text: $searchText, prompt: Text("Search...").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .padding()
            .glassCardStyle(cornerRadius: 25)
            
            // Мрежа с елементи
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems) { item in
                        IconSelectItemView(
                            item: item,
                            isSelected: selection.contains(item.id),
                            iconSize: iconSize,      // Подаваме размера
                            useIconColor: useIconColor, // Подаваме избора на цвят
                            dissableText: dissableText
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
                        .padding(2)

                    }
                }
                .padding(.vertical, 1)
                Spacer(minLength: 150)
            }
        }
        .padding(.horizontal)
    }
}

/// Помощен изглед за един елемент от мрежата.
private struct IconSelectItemView<Item: SelectableItem>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let item: Item
    let isSelected: Bool
    let iconSize: CGSize
    let useIconColor: Bool
    let dissableText: Bool
    let action: () -> Void

    var body: some View {
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        // Обвиваме целия изглед в Button, за да направим цялата карта кликаема.
        Button(action: action) {
            VStack(spacing: 0) {
                // Изглед за иконата
                ZStack {
                    // Първо проверяваме за икона-снимка
                    if let iconName = item.iconName, let uiImage = UIImage(named: iconName) {
                        Image(uiImage: uiImage)
                            .resizable()
                            // Условно задаваме renderingMode
                            .renderingMode(useIconColor ? .original : .template)
                            .scaledToFit()
                    }
                    // Ако няма снимка, проверяваме за икона-текст
                    else if let iconText = item.iconText {
                        Text(iconText)
                            .font(.system(size: iconSize.height * 0.7)) // Мащабираме шрифта спрямо размера
                            .fontWeight(.bold)
                    }
                    // Ако няма нищо, празен placeholder
                    else {
                        Rectangle()
                            .fill(Color.clear)
                    }
                }
                .frame(width: iconSize.width, height: iconSize.height) // Използваме новия параметър за размер
                if !dissableText{
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .frame(height: 40)
                }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .padding(10)
            .glassCardStyle(cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2.5)
            )
            .contentShape(Rectangle())

        }
        .buttonStyle(.plain) // Премахваме стандартния стил на бутона.
        // --- КРАЙ НА ПРОМЯНАТА ---
    }
}

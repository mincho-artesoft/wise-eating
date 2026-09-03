import SwiftUI

struct GoalsDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Входни данни
    let achieved: Int
    let total: Int
    let onDismiss: () -> Void
    let items: [NutriItem]?
    let allConsumedFoods: [FoodItem: Double]

    @State private var localSelectedNutrientID: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Константи за оформление
    private var ringsPerRow: Int {
           // 6 за телефони, 12 за таблети/landscape
           sizeClass == .regular ? 12 : 6
       }
    private let ringSize:      CGFloat = 40
    private let ringSpacing:   CGFloat = 10
    private let labelSpacing:  CGFloat = 6
    private let ringPadding:   CGFloat = 6
    private var ringCellWidth:  CGFloat { ringSize + ringPadding * 2 }
    private var labelHeight:    CGFloat { ringSize * 0.18 * 1.25 }
    private var ringCellHeight: CGFloat {
        ringSize + labelSpacing
        + ringSize * 0.22 * 1.25 * 2
        + ringPadding * 2 + 4
    }

    // Обновен init
    init(achieved: Int, total: Int, onDismiss: @escaping () -> Void, items: [NutriItem]?, allConsumedFoods: [FoodItem: Double]) {
        self.achieved = achieved
        self.total = total
        self.onDismiss = onDismiss
        self.items = items
        self.allConsumedFoods = allConsumedFoods
    }
    
    private var filteredFoods: [(food: FoodItem, grams: Double)] {
        guard let selectedNutrientID = localSelectedNutrientID else {
            return allConsumedFoods
                .map { (food: $0.key, grams: $0.value) }
                .sorted { $0.food.name < $1.food.name }
        }

        let foodsWithNutrient = allConsumedFoods.filter { (food, _) in
            if let (value, _) = food.value(of: selectedNutrientID), value > 0 {
                return true
            }
            return false
        }
        
        return foodsWithNutrient
            .map { (food: $0.key, grams: $0.value) }
            .sorted { (item1, item2) in
                let amount1 = item1.food.amount(of: selectedNutrientID, grams: item1.grams)
                let amount2 = item2.food.amount(of: selectedNutrientID, grams: item2.grams)
                return amount1 > amount2
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Навигационната лента
            HStack {
                Button("Close") { onDismiss() }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20).foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Text("Priority Nutrients").font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Button("Close") {}.hidden().disabled(true).padding(.horizontal, 10).padding(.vertical, 5)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            .padding(.horizontal, 10)
            // Външният VStack подрежда статичното съдържание и скролиращия се списък
            VStack(spacing: 16) {
                // 1. Статични елементи (пръстени и прогрес бар)
                buildRingGrid()
                
                if let id = localSelectedNutrientID, let item = items?.first(where: { $0.nutrientID == id }) {
                    NutrientProgressBar(item: item)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .frame(height: 100)
                        .padding(.horizontal, 10)

                }
                
                // 2. Секция със скролиращия се списък с храни
                // Заглавието е ИЗВЪН ScrollView
                Text(localSelectedNutrientID == nil ? "All Consumed Foods" : "Foods Containing Selected Nutrient")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.top, localSelectedNutrientID != nil ? 10 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)

                if filteredFoods.isEmpty {
                    // 3а. Показваме placeholder, ако няма храни
                    ContentUnavailableView("No Foods to Display", systemImage: "fork.knife.circle")
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .padding(.vertical, 40)
                        .glassCardStyle(cornerRadius: 15)
                        .padding(.horizontal, 10)


                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            Spacer(minLength: 10)
                            ForEach(filteredFoods, id: \.food.id) { item in
                                ConsumedFoodRowView(
                                    item: item.food,
                                    grams: item.grams,
                                    highlightedNutrientID: localSelectedNutrientID
                                )
                            }
                            Spacer(minLength: 150)
                        }
                    }
                    .padding(.horizontal, 10)
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
                
                // 4. Spacer(), който избутва всичко нагоре и разпъва VStack
                Spacer()
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func buildRingGrid() -> some View {
        switch items {
        case .some(let nutrientItems) where !nutrientItems.isEmpty:
            // 3. Взимаме динамичната стойност
            let currentRingsPerRow = self.ringsPerRow
            
            let pages = stride(from: 0, to: nutrientItems.count, by: currentRingsPerRow)
                .map { Array(nutrientItems[$0 ..< min($0 + currentRingsPerRow, nutrientItems.count)]) }
            
            // Премахваме GeometryReader
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { idx in
                        // Използваме .fixed, за да запазим размера на иконите консистентен
                        let cols = Array(
                            repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing),
                            count: currentRingsPerRow
                        )
                        
                        LazyVGrid(columns: cols, spacing: ringSpacing) {
                            ForEach(pages[idx]) { item in
                                ringButton(for: item)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: ringCellHeight)
                        // 4. Използваме containerRelativeFrame вместо pageWidth от GeometryReader
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .frame(height: ringCellHeight + ringPadding * 2)
            .padding(.top, 6)
            
        case .some: EmptyView()
        case .none: ProgressView().frame(height: ringCellHeight + ringPadding * 2).progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
        }
    }

    private func ringButton(for item: NutriItem) -> some View {
           // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
           Button(action: {
               withAnimation {
                   if localSelectedNutrientID == item.nutrientID {
                       localSelectedNutrientID = nil
                   } else {
                       localSelectedNutrientID = item.nutrientID
                   }
               }
           }) {
               // 1. NutrientRingView вече няма рамка, но все още използва isSelected за цвета на текста си.
               NutrientRingView(
                   item: item,
                   diameter: ringSize,
                   isSelected: item.nutrientID == localSelectedNutrientID,
                   accent: effectManager.currentGlobalAccentColor
               )
               // 2. Прилагаме glassCardStyle ВЪТРЕ в label-а на бутона.
               .glassCardStyle(cornerRadius: 15)
           }
           .buttonStyle(.plain)
           // 3. Прилагаме рамката за селекция като overlay ВЪРХУ целия бутон.
           //    .strokeBorder гарантира, че рамката ще се вижда.
           .overlay(
               RoundedRectangle(cornerRadius: 15)
                   .strokeBorder(
                       item.nutrientID == localSelectedNutrientID ? item.color.opacity(0.7) : Color.clear,
                       lineWidth: 2.5 // Може да увеличите леко дебелината за по-добър ефект
                   )
           )
           .animation(.easeInOut, value: item.nutrientID == localSelectedNutrientID)
           // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
       }
}

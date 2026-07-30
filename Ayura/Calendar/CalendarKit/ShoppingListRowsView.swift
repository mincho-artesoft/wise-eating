import SwiftUI

// UndoBarView остава без промяна
private struct UndoBarView: View {
    let onUndo: () -> Void
    var onCommit: () -> Void
    let itemsPendingCount: Int
    
    let timerDuration: TimeInterval = 10.0
    @State private var timeRemaining: TimeInterval
    @State private var internalTimer: Timer?

    private let backgroundColor = Color.black.opacity(0.8)
    private let foregroundColor = Color.white
    private let progressColor = Color.white.opacity(0.5)

    init(itemsPendingCount: Int, onUndo: @escaping () -> Void, onCommit: @escaping () -> Void) {
        self.itemsPendingCount = itemsPendingCount
        self.onUndo = onUndo
        self.onCommit = onCommit
        _timeRemaining = State(initialValue: timerDuration)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(progressColor)
                    .frame(width: geometry.size.width * (CGFloat(timeRemaining / timerDuration)))
                    .animation(.linear(duration: 0.1), value: timeRemaining)
            }
            
            HStack {
                Text("\(itemsPendingCount) item\(itemsPendingCount > 1 ? "s" : "") bought")
                    .foregroundColor(foregroundColor)
                    .font(.system(size: 13))
                
                Spacer()
                
                Text("\(Int(ceil(timeRemaining)))s")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(foregroundColor.opacity(0.8))
                    .padding(.horizontal, 8)

                Button(action: {
                    self.stopTimer()
                    self.onUndo()
                }) {
                    Text("Undo")
                        .foregroundColor(foregroundColor)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 36)
        .background(backgroundColor)
        .cornerRadius(8)
        .clipped()
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }
    
    private func startTimer() {
        stopTimer()
        internalTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            DispatchQueue.main.async {
                if self.timeRemaining > 0.05 {
                    self.timeRemaining -= 0.1
                } else {
                    self.timeRemaining = 0
                    self.stopTimer()
                    self.onCommit()
                }
            }
        }
    }
    
    private func stopTimer() {
        internalTimer?.invalidate()
        internalTimer = nil
    }
}


struct ShoppingListRowsView: View {
    let items: [ShoppingListItemPayload]
    var onCommit: (([ShoppingListItemPayload]) -> Void)?

    @ObservedObject private var effectManager = EffectManager.shared
    @State private var itemsPendingPurchase: [ShoppingListItemPayload] = []
    
    private var unboughtItems: [ShoppingListItemPayload] {
        items.filter { item in
            !item.isBought && !itemsPendingPurchase.contains(where: { pendingItem in pendingItem.id == item.id })
        }
    }
    
    private var allItemsBought: Bool {
        items.filter { !$0.isBought }.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unboughtItems, id: \.id) { item in
                        rowContent(for: item)
                    }
                    
                    if !items.isEmpty && unboughtItems.isEmpty {
                        allBoughtMessage()
                    }
                }
                .padding(.top, 4)
            }
            
            if !itemsPendingPurchase.isEmpty {
                UndoBarView(
                    itemsPendingCount: itemsPendingPurchase.count,
                    onUndo: {
                        itemsPendingPurchase.removeAll()
                    },
                    onCommit: {
                        let itemsToCommit = itemsPendingPurchase
                        itemsPendingPurchase.removeAll()
                        onCommit?(itemsToCommit)
                    }
                )
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(itemsPendingPurchase.count)
            }
        }
        .clipped()
        .animation(.default, value: itemsPendingPurchase)
        .animation(.default, value: unboughtItems.count)
        .onDisappear {
            if !itemsPendingPurchase.isEmpty {
                let itemsToCommit = itemsPendingPurchase
                itemsPendingPurchase.removeAll()
                onCommit?(itemsToCommit)
            }
        }
    }
    
    @ViewBuilder
    private func rowContent(for item: ShoppingListItemPayload) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                .font(.system(size: 14))
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        itemsPendingPurchase.append(item)
                    }
                }

            Text(item.name)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
            
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
            let quantityDisplay = UnitConversion.formatGramsToGramsOrOunces(item.quantity)
            
            Text("\(quantityDisplay.value) \(quantityDisplay.unit)")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
            // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
        }
    }

    @ViewBuilder
    private func allBoughtMessage() -> some View {
        HStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("All items bought!")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(effectManager.currentGlobalAccentColor)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

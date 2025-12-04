import SwiftUI
import SwiftData

struct TransactionHistoryContent: View {
    let item: StorageItem
    @ObservedObject private var effectManager = EffectManager.shared

    @Query private var transactions: [StorageTransaction]
    
    init(item: StorageItem) {
        self.item = item
        
        let foodID = item.food?.persistentModelID
        let profileID = item.owner?.persistentModelID
        
        let predicate = #Predicate<StorageTransaction> { transaction in
            transaction.food?.persistentModelID == foodID &&
            transaction.profile?.persistentModelID == profileID
        }
        
        self._transactions = Query(filter: predicate, sort: \StorageTransaction.date, order: .reverse)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current Status")
                            .font(.headline.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Spacer()
                    }

                    Divider()
                        .background(effectManager.currentGlobalAccentColor.opacity(0.9))

                    HStack {
                        Text("Available Quantity")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Spacer()
                        
                        // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
                        let availableDisplay = UnitConversion.formatGramsToGramsOrOunces(item.totalQuantity)
                        
                        Text(availableDisplay.value)
                            .fontWeight(.bold)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        + Text(" \(availableDisplay.unit)")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----

                    }
                    .font(.subheadline)
                }
                .padding()
                .glassCardStyle(cornerRadius: 15)

                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock.arrow.circlepath")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    } description: {
                        Text("No transactions have been recorded for this item yet.")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 15)
                } else {
                    ForEach(transactions) { transaction in
                        TransactionRowView(transaction: transaction)
                            .padding()
                            .glassCardStyle(cornerRadius: 15)
                    }
                }
                Spacer(minLength: 150)
            }
            .padding(.horizontal)
            .padding(.top, 8)
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
        .background(Color.clear)
    }
}

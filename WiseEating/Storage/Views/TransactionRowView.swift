import SwiftUI
import SwiftData

struct TransactionRowView: View {
    let transaction: StorageTransaction
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: transaction.type.iconName)
                .font(.title2)
                .foregroundStyle(transaction.type.color)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(transaction.type.rawValue)
                    .fontWeight(.bold)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Text(transaction.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            
            Spacer()
            
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
            let quantityDisplay = UnitConversion.formatGramsToGramsOrOunces(abs(transaction.quantityChange))
            let sign = transaction.quantityChange >= 0 ? "+" : "-"
            
            Text("\(sign)\(quantityDisplay.value) \(quantityDisplay.unit)")
                .font(.system(.body, design: .monospaced))
            // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
                .fontWeight(.medium)
                .foregroundStyle(transaction.quantityChange >= 0 ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

import SwiftUI

struct AnalyticsToolbarView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    @Binding var selectedTimeRange: AnalyticsView.TimeRange
    let customStartDate: Date?
    let customEndDate: Date?
    let onCustomDateTapped: () -> Void

    // --- НАЧАЛО НА ПРОМЯНАТА ---
    private var formattedDateRange: String {
        guard let start = customStartDate, let end = customEndDate else {
            return "Select Range"
        }
        let formatter = DateFormatter()
        // Проверяваме дали има зададен глобален формат и го използваме
        if !GlobalState.dateFormat.isEmpty {
            formatter.dateFormat = GlobalState.dateFormat
        } else {
            // Ако няма, използваме стандартен кратък формат
            formatter.dateStyle = .short
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    // --- КРАЙ НА ПРОМЯНАТА ---

    var body: some View {
        HStack {
            Text("Analytics")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
            
            if selectedTimeRange == .custom {
                Button(action: onCustomDateTapped) {
                    Text(formattedDateRange)
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .glassCardStyle(cornerRadius: 20)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut, value: selectedTimeRange)
    }
}

// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Fitness/Views/NetBalanceRingView.swift

import SwiftUI

struct NetBalanceRingView: View {
    // MARK: - Environment & Managers
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Input Properties
    let netCalorieBalance: Double
    let totalCaloriesConsumed: Double
    
    
    
    // MARK: - Computed Properties
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/4): Актуализираме 'color', за да има неутрален цвят ---
    private var color: Color {
        if netCalorieBalance > 0 {
            return .orange // Surplus
        } else if netCalorieBalance < 0 {
            return .green // Deficit
        } else {
            return effectManager.currentGlobalAccentColor // Neutral
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (1/4) ---

    private var progress: Double {
        guard totalCaloriesConsumed > 0 else { return 0.0 }
        return min(abs(netCalorieBalance) / totalCaloriesConsumed, 1.0)
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА (2/4): Добавяме изчисляемо свойство за иконата ---
    private var iconName: String {
        if netCalorieBalance > 0 {
            return "arrow.up.circle.fill"
        } else if netCalorieBalance < 0 {
            return "arrow.down.circle.fill"
        } else {
            return "minus.circle.fill"
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (2/4) ---

    // --- НАЧАЛО НА ПРОМЯНАТА (3/4): Добавяме изчисляемо свойство за текста ---
    private var balanceText: String {
        if netCalorieBalance > 0 {
            return String(format: "+%.0f", netCalorieBalance)
        } else if netCalorieBalance < 0 {
            return String(format: "%.0f", netCalorieBalance)
        } else {
            return "0"
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (3/4) ---
    
    // MARK: - Body
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 6)
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.2))

            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear(duration: 0.5), value: progress)
                
            VStack(spacing: 1) {
                // --- НАЧАЛО НА ПРОМЯНАТА (4/4): Използваме новите изчисляеми свойства ---
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(color)

                Text(balanceText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                // --- КРАЙ НА ПРОМЯНАТА (4/4) ---
                
                Text("kcal")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
        }
    }
}

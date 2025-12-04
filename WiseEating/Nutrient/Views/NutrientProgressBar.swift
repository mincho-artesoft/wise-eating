import SwiftUI

struct NutrientProgressBar: View {
    // MARK: - Вход
    let item: NutriItem          // NutriItem: label, unit, amount, dailyNeed, upperLimit, color
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Геометрия
    private let barHeight: CGFloat = 8
    // ▼ под бара
    private var arrowBelow: CGFloat { barHeight + 2 }
    private var textBelow:  CGFloat { barHeight + 16 }
    // ▲ над бара
    private let arrowAbove: CGFloat = -10
    private let textAbove:  CGFloat = -16

    // MARK: - Скалиране
    private let bufferFactor: Double = 1.2                // +20 %
    /// Референтна точка: UL ако има, иначе RDI (дневна нужда)
    private var reference: Double { item.upperLimit ?? item.dailyNeed ?? 1 }
    /// Макс. стойност на лентата (референт × 1.2)
    private var maxValue: Double { max(reference * bufferFactor, 1) }
    /// Прогрес (0…1)
    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(item.amount / maxValue, 1)
    }

    // MARK: - Логика за аларма (червен цвят)
    private var isAlert: Bool {
        if let ul = item.upperLimit {
            if let dn = item.dailyNeed, item.amount < dn { return true }
            return item.amount > ul
        } else if let dn = item.dailyNeed {
            return item.amount < dn
        }
        return false
    }

    // MARK: - Данни за стрелките
    private var dailyNeed:  Double  { item.dailyNeed  ?? 0 }
    private var upperLimit: Double? { item.upperLimit }

    /// Позиция (0…1) на ▼ RDI
    private var needRatio: Double {
        guard maxValue > 0 else { return 0 }
        return min(dailyNeed / maxValue, 1)
    }

    /// Позиция (0…1) на ▼ UL (ако има UL)
    private var ulRatio: Double {
        guard let ul = upperLimit, maxValue > 0 else { return 1 }
        return min(ul / maxValue, 1)
    }

    /// Позиция (0…1) на ▲ текущото количество
    private var currentRatio: Double { progress }

    // MARK: - Защита от „излизане“ на етикета (▲ текуща стойност)
    @State private var currentValueLabelWidth: CGFloat = 0
    private struct _CurrentValueWidthKey: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    // MARK: - Тяло
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Етикет + единица (единицата е по-малка и със secondary цвят)
            HStack(spacing: 4) {
                Text(item.label)
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                VStack(spacing: 0) {
                    Spacer()
                    Text(item.unit)
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                .padding(.bottom, 3)
            }
            .padding(.leading, 8)

            GeometryReader { geo in
                let W = geo.size.width

                ZStack(alignment: .leading) {
                    // --- ФОН ---
                    Capsule()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .frame(height: barHeight)

                    // --- ЗАПЪЛВАНЕ ---
                    Capsule()
                        .fill(isAlert ? Color.red.opacity(0.7) : item.color)
                        .frame(width: W * progress, height: barHeight)

                    // --- ▼ RDI ---
                    Triangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .frame(width: 10, height: 6)
                        .offset(x: W * needRatio - 5, y: arrowBelow)

                    // --- ▼ UL (ако има) ---
                    if upperLimit != nil {
                        Triangle()
                            .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .frame(width: 10, height: 6)
                            .offset(x: W * ulRatio - 5, y: arrowBelow)
                    }

                    // --- ▲ Текущо количество ---
                    TriangleUp()
                        .fill(isAlert ? Color.red.opacity(0.7) : effectManager.currentGlobalAccentColor)
                        .frame(width: 10, height: 6)
                        .offset(x: W * currentRatio - 5, y: arrowAbove)
                }
                // --- ЧИСЛА ПОД ▼ стрелките ---
                // ▼ RDI
                .overlay(alignment: .topLeading) {
                    Text("\(Int(dailyNeed))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .position(x: W * needRatio, y: textBelow)
                }
                // ▼ UL (ако има)
                .overlay(alignment: .topLeading) {
                    if let ul = upperLimit {
                        Text("\(Int(ul))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .position(x: W * ulRatio, y: textBelow)
                    }
                }
                // ▲ текущо количество — със защитено позициониране в рамките на бара
                .overlay(alignment: .topLeading) {
                    // „Суровата“ позиция (център на етикета) според прогреса
                    let xRaw = W * currentRatio
                    // Безопасни граници така, че етикетът да не излиза извън бара
                    let edgePadding: CGFloat = 6
                    let half = currentValueLabelWidth / 2
                    // clamp: [leftBound ... rightBound]
                    let leftBound  = edgePadding + half
                    let rightBound = W - edgePadding - half
                    let xSafe = min(max(xRaw, leftBound), rightBound)

                    Text(
                        item.amount.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(item.amount))
                        : String(format: "%.1f", item.amount)
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isAlert ? .red : effectManager.currentGlobalAccentColor.opacity(0.8))
                    // измерваме реалната ширина на текста
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: _CurrentValueWidthKey.self, value: g.size.width)
                        }
                    )
                    .onPreferenceChange(_CurrentValueWidthKey.self) { w in
                        currentValueLabelWidth = w
                    }
                    // позиционираме с „безопасния“ x
                    .position(x: xSafe, y: textAbove)
                }
                // Анимация при промяна
                .animation(.easeInOut, value: item.amount)
            }
            .padding(.top, 20)
            // + място нагоре за ▲ и числото
            .frame(height: barHeight + 44)
        }
        .padding(8)
        .glassCardStyle(cornerRadius: 20)
    }
}

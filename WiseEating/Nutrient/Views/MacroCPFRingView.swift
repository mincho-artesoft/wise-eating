import SwiftUI

struct MacroCPFRingView: View {
    let proportions: [NutrientProportionData]
    @ObservedObject private var effectManager = EffectManager.shared

    // Стилизация
    let centralContentDiameter: CGFloat
    let donutRingThickness: CGFloat
    let canalRingThickness: CGFloat
    let ringTrackColor: Color
    
    // Стойност за нормализация
    let totalReferenceValue: Double?

    // Изчисляеми променливи за геометрията (същите като в оригинала)
    private var canalRingPathDiameter: CGFloat { centralContentDiameter + canalRingThickness }
    private var canalRingOuterDiameter: CGFloat { centralContentDiameter + (2 * canalRingThickness) }
    private var arcDrawingRadius: CGFloat { (canalRingOuterDiameter / 2) + (donutRingThickness / 2) }
    private var totalDiameter: CGFloat { canalRingOuterDiameter + (2 * donutRingThickness) }
    private var arcCenter: CGPoint { CGPoint(x: totalDiameter / 2, y: totalDiameter / 2) }

    var body: some View {
        // Логиката за изчисляване на сегментите остава същата
        let effectiveTotalForNormalization: Double = {
            if let refTotal = totalReferenceValue, refTotal > 0 {
                return refTotal
            } else {
                let sumOfProportions = proportions.reduce(0) { $0 + $1.value }
                return sumOfProportions > 0 ? sumOfProportions : 1.0
            }
        }()

        var allSegmentsIncludingGap: [NutrientProportionData] {
            let usedTotal = proportions.reduce(0) { $0 + $1.value }
            let remaining = max(effectiveTotalForNormalization - usedTotal, 0)
            
            var currentProportions = proportions
            if remaining > 0.00001 {
                 currentProportions.append(NutrientProportionData(name: "Remaining",
                                                        value: remaining,
                                                        color: .clear))
            }
            return currentProportions
        }
        
        ZStack {

            Circle()
                .stroke(style: StrokeStyle(lineWidth: donutRingThickness))
                .foregroundColor(ringTrackColor) // Използваме цвета за "пътя"
                // Диаметърът на този кръг трябва да е два пъти радиуса на чертане,
                // за да съвпадне перфектно с арките на сегментите.
                .frame(width: arcDrawingRadius * 2, height: arcDrawingRadius * 2)
            
            ArcSegmentsView(
                proportions: allSegmentsIncludingGap,
                effectiveTotalForNormalization: effectiveTotalForNormalization,
                arcCenter: arcCenter,
                arcDrawingRadius: arcDrawingRadius,
                donutRingThickness: donutRingThickness
            )

            // ПРОМЯНА: Централното съдържание е заменено с буквите C/P/F
            HStack(spacing: centralContentDiameter * 0.08) {
                Text("C")
                    .foregroundColor(colorForMacro(named: "Carbs"))
                Text("P")
                    .foregroundColor(colorForMacro(named: "Protein"))
                Text("F")
                    .foregroundColor(colorForMacro(named: "Fat"))
            }
            .font(.system(size: centralContentDiameter * 0.4, weight: .bold, design: .rounded))
            
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .drawingGroup()
    }
    
    /// Помощна функция за намиране на цвета на макронутриента
    private func colorForMacro(named macroName: String) -> Color {
        // Ако има пропорция с това име и стойност по-голяма от 0, връщаме нейния цвят.
        if let proportion = proportions.first(where: { $0.name.contains(macroName) && $0.value > 0.01 }) {
            return proportion.color
        }
        // В противен случай връщаме неутрален сив цвят.
        return effectManager.currentGlobalAccentColor.opacity(0.8)
    }
}

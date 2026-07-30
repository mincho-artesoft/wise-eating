import SwiftUI

/// Един пръстен + 0–2 редов етикет. Олекотен и БЕЗ клипване на щриха.
struct NutrientRingView: View {
    // ... (всички properties остават същите) ...
    let item: NutriItem
    var diameter:   CGFloat = 70
    var isSelected: Bool    = false
    var animate: Bool = true
    var accent: Color = .primary
    // ... (всички computed properties остават същите) ...
    private var ringWidth:    CGFloat { diameter * 0.11 }
    private let labelSpacing: CGFloat = 6
    private var labelFontSize: CGFloat { diameter * 0.22 }
    private let labelLines:    Int     = 2
    private var labelHeight: CGFloat { labelFontSize * 1.25 * CGFloat(labelLines) }
    private var totalHeight: CGFloat { diameter + labelSpacing + labelHeight }
    private var denominator: Double? { item.dailyNeed }
    private var progress: Double {
        guard let denom = denominator, denom > 0 else { return 1 }
        return min(item.amount / denom, 1)
    }
    private var percent: Int {
        guard let dn = item.dailyNeed, dn > 0 else { return 100 }
        return item.amount >= dn ? 100 : Int((item.amount / dn) * 100)
    }
    private var percentColor: Color {
        if let ul = item.upperLimit, item.amount >= ul { return .red }
        if let dn = item.dailyNeed, dn > 0 { return item.amount >= dn ? .green : .red }
        return accent
    }

    var body: some View {
        VStack(spacing: labelSpacing) {

            ZStack {
                let ringInset = ringWidth / 2 + 0.5

                Circle()
                    .inset(by: ringInset)
                    .stroke(accent.opacity(0.18), lineWidth: ringWidth)

                Circle()
                    .inset(by: ringInset)
                    .trim(from: 0, to: progress)
                    .stroke(item.color, style: .init(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(percent)%")
                    .font(.system(size: diameter * 0.24, weight: .bold, design: .rounded))
                    .foregroundStyle(percentColor)
                    .monospacedDigit()
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
            .drawingGroup()
            .animation(animate ? .easeInOut(duration: 0.35) : nil, value: progress)

            Text(item.label)
                .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                .frame(width: diameter, height: labelHeight, alignment: .top)
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .lineLimit(labelLines)
                .minimumScaleFactor(0.7)
        }
        .frame(width: diameter, height: totalHeight, alignment: .top)
        .padding(6)
    }
}

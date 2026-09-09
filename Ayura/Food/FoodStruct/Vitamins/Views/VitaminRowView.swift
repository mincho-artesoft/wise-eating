import SwiftUI

struct VitaminRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let vitamin: Vitamin
    let demographic: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // Увеличаваме малко разстоянието
            HStack {
                Text(vitamin.name)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(vitamin.unit)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
            }
            
            // Разделителна линия за по-добра визуална йерархия
            Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))

            if let demo = demographic,
               let req = vitamin.requirements.first(where: { $0.demographic == demo }) {
                // Показва изискванията за конкретния профил
                VStack(alignment: .leading, spacing: 4) {
                    Text(req.demographic)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    requirementView(for: req)
                }
            } else {
                // Показва изискванията за всички групи, ако няма профил
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily Needs by Group")
                         .font(.caption.weight(.semibold))
                         .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    ForEach(vitamin.requirements) { req in
                        requirementView(for: req, showDemographic: true)
                    }
                }
            }
        }
        // ПРОМЯНА 1: Задаваме цвят на текста за целия VStack
        .foregroundColor(effectManager.currentGlobalAccentColor)
        // ПРОМЯНА 2: Добавяме вътрешно отстояние, за да не е залепен текстът за ръба на картата
        .padding()
        // ПРОМЯНА 3: Прилагаме стила на стъклената карта
        .glassCardStyle(cornerRadius: 15)
    }

    @ViewBuilder
    private func requirementView(for req: Requirement, showDemographic: Bool = false) -> some View {
        let formatter: NumberFormatter = {
            let nf = NumberFormatter()
            nf.minimumFractionDigits = 0
            nf.maximumFractionDigits = 2
            nf.numberStyle = .decimal
            return nf
        }()

        let dailyNeedFormatted = formatter.string(from: NSNumber(value: req.dailyNeed)) ?? "\(req.dailyNeed)"

        HStack {
            if showDemographic {
                Text(req.demographic)
                    .font(.caption2)
                    .frame(minWidth: 140, alignment: .leading) // Подравняване за прегледност
            }
            
            Text("Min: \(dailyNeedFormatted)")
                .font(.caption2)

            if let upper = req.upperLimit {
                let upperFormatted = formatter.string(from: NSNumber(value: upper)) ?? "\(upper)"
                Text("Max: \(upperFormatted)")
                    .font(.caption2)
            }
            Spacer()
        }
    }
}

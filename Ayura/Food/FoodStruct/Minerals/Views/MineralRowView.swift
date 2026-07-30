import SwiftUI

struct MineralRowView: View {
    let mineral: Mineral
    let demographic: String?
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Хедър с името и мерната единица
            HStack {
                Text(mineral.name)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(mineral.unit)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
            }

            Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))

            // Секция с препоръките
            if let demo = demographic,
               let req = mineral.requirements.first(where: { $0.demographic == demo }) {
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
                    ForEach(mineral.requirements) { req in
                        requirementView(for: req, showDemographic: true)
                    }
                }
            }
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        // ПРОМЯНА: Добавяме padding и glassCardStyle, за да го превърнем в карта
        .padding()
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

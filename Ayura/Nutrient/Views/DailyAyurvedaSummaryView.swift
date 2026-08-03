import SwiftUI

struct DailyAyurvedaMealSummary: Identifiable {
    let id: UUID
    let name: String
    let computed: AyurvedaDisplayMath.Computed
}

struct DailyAyurvedaSummaryRow: View {
    let computation: AyurvedaIngredientComputation
    let target: AyurvedaDoshaDistribution?
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Spacer()
            doshaCard(.vata, value: computation.computed?.vata)
            Spacer()
            doshaCard(.pitta, value: computation.computed?.pitta)
            Spacer()
            doshaCard(.kapha, value: computation.computed?.kapha)
            Spacer()
            fitCard
            Spacer()
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily Ayurveda summary")
    }

    private func doshaCard(
        _ dosha: AyurvedaDosha,
        value: Int?
    ) -> some View {
        Button(action: onTap) {
            DailyAyurvedaRingCard(
                title: dosha.displayName,
                value: value.map(AyurvedaDisplayMath.valueString) ?? "—",
                fraction: value.map {
                    AyurvedaDisplayMath.barFraction($0)
                } ?? 0,
                color: value.map {
                    profileAwareColor(value: $0, dosha: dosha)
                } ?? neutralColor,
                systemImage: value.map {
                    AyurvedaDoshaEffectPresentation(value: $0).systemImage
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var fitCard: some View {
        Button(action: onTap) {
            DailyAyurvedaRingCard(
                title: "Fit",
                value: fitLabel,
                fraction: fitFraction,
                color: fitColor,
                systemImage: fitIcon
            )
        }
        .buttonStyle(.plain)
    }

    private var fit: AyurvedaFoodFitPresentation? {
        guard let computed = computation.computed, let target else {
            return nil
        }
        return AyurvedaFoodFitPresentation.make(
            target: target,
            vata: computed.vata,
            pitta: computed.pitta,
            kapha: computed.kapha,
            rasa: [],
            virya: computed.virya,
            gunas: []
        )
    }

    private var fitLabel: String {
        guard computation.computed != nil else { return "—" }
        guard let fit else { return "?" }
        switch fit.direction {
        case .supportive: return "Good"
        case .mixed: return "Mixed"
        case .lessSupportive: return "Poor"
        }
    }

    private var fitFraction: Double {
        guard let fit else { return 0 }
        return min(1, max(0, (fit.score + 2) / 4))
    }

    private var fitColor: Color {
        guard computation.computed != nil, let fit else {
            return neutralColor
        }
        return color(for: fit.direction)
    }

    private var fitIcon: String? {
        guard computation.computed != nil else { return nil }
        guard let fit else { return "person.crop.circle.badge.questionmark" }
        switch fit.direction {
        case .supportive: return "leaf.fill"
        case .mixed: return "equal.circle.fill"
        case .lessSupportive: return "arrow.down.right.circle.fill"
        }
    }

    private func profileAwareColor(
        value: Int,
        dosha: AyurvedaDosha
    ) -> Color {
        guard let target else {
            return effectColor(value)
        }
        let contribution = Double(-value) * target[dosha]
        if contribution > 0.05 { return Color("AyurvedaPacify") }
        if contribution < -0.05 { return Color("AyurvedaAggravate") }
        return neutralColor
    }

    private func effectColor(_ value: Int) -> Color {
        if value < 0 { return Color("AyurvedaPacify") }
        if value > 0 { return Color("AyurvedaAggravate") }
        return neutralColor
    }

    private func color(
        for direction: AyurvedaFoodFitPresentation.Direction
    ) -> Color {
        switch direction {
        case .supportive: Color("AyurvedaPacify")
        case .mixed: neutralColor
        case .lessSupportive: Color("AyurvedaAggravate")
        }
    }

    private var neutralColor: Color {
        Color("AyurvedaNeutral")
    }
}

private struct DailyAyurvedaRingCard: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let title: String
    let value: String
    let fraction: Double
    let color: Color
    let systemImage: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption2)
                    }
                    Text(value)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(color)
            }
            .frame(width: 60, height: 60)

            Text(title)
                .font(.caption)
                .foregroundStyle(
                    effectManager.currentGlobalAccentColor.opacity(0.8)
                )
        }
        .padding(10)
        .glassCardStyle(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct DailyAyurvedaDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let date: Date
    let profileName: String
    let computation: AyurvedaIngredientComputation
    let target: AyurvedaDoshaDistribution?
    let meals: [DailyAyurvedaMealSummary]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let computed = computation.computed {
                        profileFitCard(computed)
                        doshaCard(computed)
                        contextCard(computed)
                        mealBreakdown
                    } else {
                        ContentUnavailableView(
                            computation.hasIngredients
                                ? "Not Enough Ayurveda Data"
                                : "No Foods for This Day",
                            systemImage: "leaf.circle",
                            description: Text(
                                computation.hasIngredients
                                    ? "At least half of the day's food weight needs Ayurveda data."
                                    : "Add foods to see the daily Ayurveda summary."
                            )
                        )
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.8)
                        )
                        .padding(.vertical, 40)
                        .glassCardStyle(cornerRadius: 20)
                    }

                    Spacer(minLength: 150)
                }
                .padding(.horizontal)
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Close", action: onDismiss)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()
            VStack(spacing: 1) {
                Text("Daily Ayurveda")
                    .font(.headline)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .opacity(0.75)
            }
            Spacer()

            Button("Close") {}
                .hidden()
                .disabled(true)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func profileFitCard(
        _ computed: AyurvedaDisplayMath.Computed
    ) -> some View {
        if let target {
            let fit = AyurvedaFoodFitPresentation.make(
                target: target,
                vata: computed.vata,
                pitta: computed.pitta,
                kapha: computed.kapha,
                rasa: [],
                virya: computed.virya,
                gunas: []
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Fit for \(profileName)")
                    .font(.title3.weight(.semibold))
                Label(fit.title, systemImage: fitIcon(fit.direction))
                    .font(.headline)
                    .foregroundStyle(fitColor(fit.direction))
                Text(fit.explanation)
                    .font(.subheadline)
                HStack(spacing: 14) {
                    profileShare("Vata", target.vata)
                    profileShare("Pitta", target.pitta)
                    profileShare("Kapha", target.kapha)
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: 20)
        } else {
            Label(
                "Create an Ayurvedic profile for \(profileName) to see personal fit.",
                systemImage: "person.crop.circle.badge.questionmark"
            )
            .font(.subheadline)
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: 20)
        }
    }

    private func doshaCard(
        _ computed: AyurvedaDisplayMath.Computed
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Dosha Effect")
                .font(.title3.weight(.semibold))
            DoshaBarsView(
                vata: computed.vata,
                pitta: computed.pitta,
                kapha: computed.kapha
            )
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    private func contextCard(
        _ computed: AyurvedaDisplayMath.Computed
    ) -> some View {
        HStack(spacing: 12) {
            Label(computed.virya.capitalized, systemImage: viryaIcon(computed.virya))
            Spacer()
            Text("Coverage \(coveragePercent)%")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private var mealBreakdown: some View {
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("By Meal")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                ForEach(meals) { meal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(meal.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Label(
                                meal.computed.virya.capitalized,
                                systemImage: viryaIcon(meal.computed.virya)
                            )
                            .font(.caption)
                        }
                        AyurvedaDoshaResultChips(
                            vata: meal.computed.vata,
                            pitta: meal.computed.pitta,
                            kapha: meal.computed.kapha
                        )
                    }
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding()
                    .glassCardStyle(cornerRadius: 16)
                }
            }
        }
    }

    private var coveragePercent: Int {
        Int((min(1, max(0, computation.coverage)) * 100).rounded())
    }

    private func profileShare(_ name: String, _ value: Double) -> some View {
        Text("\(name) \(Int((value * 100).rounded()))%")
            .font(.caption.weight(.semibold))
    }

    private func viryaIcon(_ virya: String) -> String {
        switch virya.lowercased() {
        case "heating": "flame.fill"
        case "cooling": "snowflake"
        default: "minus.circle.fill"
        }
    }

    private func fitIcon(
        _ direction: AyurvedaFoodFitPresentation.Direction
    ) -> String {
        switch direction {
        case .supportive: "leaf.fill"
        case .mixed: "equal.circle.fill"
        case .lessSupportive: "arrow.down.right.circle.fill"
        }
    }

    private func fitColor(
        _ direction: AyurvedaFoodFitPresentation.Direction
    ) -> Color {
        switch direction {
        case .supportive: Color("AyurvedaPacify")
        case .mixed: Color("AyurvedaNeutral")
        case .lessSupportive: Color("AyurvedaAggravate")
        }
    }
}

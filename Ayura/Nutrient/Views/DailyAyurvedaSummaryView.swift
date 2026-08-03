import SwiftUI

struct DailyAyurvedaMealSummary: Identifiable {
    let id: UUID
    let name: String
    let computation: AyurvedaIngredientComputation
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
    @State private var selectedMealID: UUID?

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
                    selectedSummaryCard

                    if !meals.isEmpty {
                        mealSelector
                    }

                    Spacer(minLength: 150)
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: meals.map(\.id)) { _, mealIDs in
            if let selectedMealID, !mealIDs.contains(selectedMealID) {
                self.selectedMealID = nil
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

    private var selectedSummaryCard: some View {
        let selected = selectedComputation
        return VStack(alignment: .leading, spacing: 14) {
            Text(selectedTitle)
                .font(.title.weight(.bold))

            if let computed = selected.computed {
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
                            .font(.subheadline.weight(.semibold))
                        Label(fit.title, systemImage: fitIcon(fit.direction))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(fitColor(fit.direction))
                        Text(fit.explanation)
                            .font(.subheadline)
                    }
                } else {
                    Label(
                        "Create an Ayurvedic profile for \(profileName) to see personal fit.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                    .font(.subheadline)
                }

                Divider()

                DoshaBarsView(
                    vata: computed.vata,
                    pitta: computed.pitta,
                    kapha: computed.kapha
                )

                Divider()

                HStack(spacing: 12) {
                    Label(
                        computed.virya.capitalized,
                        systemImage: viryaIcon(computed.virya)
                    )
                    Spacer()
                    Text("Coverage \(coveragePercent(for: selected))%")
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Label(
                    selected.hasIngredients
                        ? "Not Enough Ayurveda Data"
                        : "No Foods in \(selectedTitle)",
                    systemImage: "leaf.circle"
                )
                .font(.headline)

                Text(
                    selected.hasIngredients
                        ? "At least half of the food weight needs Ayurveda data."
                        : "Add foods to this meal to see its Ayurveda summary."
                )
                .font(.subheadline)
                .opacity(0.76)
            }
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 20)
        .animation(.easeInOut(duration: 0.2), value: selectedMealID)
    }

    private var mealSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    scopeChip(
                        title: "Whole day",
                        systemImage: "calendar",
                        mealID: nil
                    )

                    ForEach(meals) { meal in
                        scopeChip(
                            title: meal.name,
                            systemImage: "fork.knife",
                            mealID: meal.id
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func scopeChip(
        title: String,
        systemImage: String,
        mealID: UUID?
    ) -> some View {
        GlassChipView(
            label: title,
            color: .blue,
            systemImage: systemImage,
            textColor: effectManager.currentGlobalAccentColor,
            isSelected: selectedMealID == mealID,
            action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedMealID = mealID
                }
            }
        )
    }

    private var selectedComputation: AyurvedaIngredientComputation {
        guard let selectedMealID,
              let meal = meals.first(where: { $0.id == selectedMealID }) else {
            return computation
        }
        return meal.computation
    }

    private var selectedTitle: String {
        guard let selectedMealID,
              let meal = meals.first(where: { $0.id == selectedMealID }) else {
            return "Whole Day"
        }
        return meal.name
    }

    private func coveragePercent(
        for computation: AyurvedaIngredientComputation
    ) -> Int {
        Int((min(1, max(0, computation.coverage)) * 100).rounded())
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

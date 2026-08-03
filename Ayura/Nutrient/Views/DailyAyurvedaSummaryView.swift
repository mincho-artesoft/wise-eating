import SwiftUI

struct DailyAyurvedaMealSummary: Identifiable {
    let id: UUID
    let name: String
    let computation: AyurvedaIngredientComputation
}

struct DailyAyurvedaSummaryRow: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let computation: AyurvedaIngredientComputation
    let target: AyurvedaDoshaDistribution?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                if let computed = computation.computed {
                    VStack(spacing: 8) {
                        doshaScale(name: "Vata", value: computed.vata)
                        doshaScale(name: "Pitta", value: computed.pitta)
                        doshaScale(name: "Kapha", value: computed.kapha)
                        scaleLabels
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Ayurvedic effects unavailable")
                        .font(.caption)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.7)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Fit")
                        .font(.caption)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.72)
                        )
                    Label(fitLabel, systemImage: fitIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(fitColor)
                }
                .frame(minWidth: 68, alignment: .trailing)
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel(
            "Daily Ayurveda. Fit \(fitLabel). Open daily details."
        )
    }

    private func doshaScale(name: String, value: Int) -> some View {
        let clampedValue = min(2, max(-2, value))
        let progress = CGFloat(2 - clampedValue) / 4
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(signedValue(clampedValue))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(doshaColor(for: clampedValue))
            }

            doshaTrack(progress: progress, color: doshaColor(for: clampedValue))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) effect \(signedValue(clampedValue))")
    }

    private func doshaTrack(progress: CGFloat, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color("AyurvedaAggravate"),
                                Color("AyurvedaNeutral"),
                                Color("AyurvedaPacify"),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.85), lineWidth: 2)
                    }
                    .offset(
                        x: max(0, (proxy.size.width - 12) * progress)
                    )
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private var scaleLabels: some View {
        HStack {
            Text("Poor")
            Spacer()
            Text("Mixed")
            Spacer()
            Text("Good")
        }
        .font(.caption2)
        .foregroundStyle(
            effectManager.currentGlobalAccentColor.opacity(0.62)
        )
        .accessibilityHidden(true)
    }

    private func signedValue(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func doshaColor(for value: Int) -> Color {
        if value < 0 { return Color("AyurvedaPacify") }
        if value > 0 { return Color("AyurvedaAggravate") }
        return neutralColor
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

    private var fitColor: Color {
        guard computation.computed != nil, let fit else {
            return neutralColor
        }
        return color(for: fit.direction)
    }

    private var fitIcon: String {
        guard computation.computed != nil else { return "minus.circle.fill" }
        guard let fit else { return "person.crop.circle.badge.questionmark" }
        switch fit.direction {
        case .supportive: return "leaf.fill"
        case .mixed: return "equal.circle.fill"
        case .lessSupportive: return "arrow.down.right.circle.fill"
        }
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

struct DailyAyurvedaDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var selectedMealID: UUID?

    let date: Date
    let profileName: String
    let computation: AyurvedaIngredientComputation
    let profileResult: AyurvedaConstitutionResult?
    let target: AyurvedaDoshaDistribution?
    let meals: [DailyAyurvedaMealSummary]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    profileConstitutionCard

                    if !meals.isEmpty {
                        mealSelector
                    }

                    selectedSummaryCard

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

    @ViewBuilder
    private var profileConstitutionCard: some View {
        if let profileResult {
            AyurvedaConstitutionResultSummary(
                result: profileResult,
                source: .selfDeclared,
                showsContextLabels: false
            )
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                    selectedMealID = selectedMealID == mealID ? nil : mealID
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

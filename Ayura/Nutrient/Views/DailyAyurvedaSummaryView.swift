import SwiftUI

struct DailyAyurvedaMealSummary: Identifiable {
    let id: UUID
    let name: String
    let computation: AyurvedaIngredientComputation
}

struct DailyAyurvedaSummaryRow: View {
    @ObservedObject private var effectManager = EffectManager.shared
    private static let scaleValues = [2, 1, 0, -1, -2]

    let computation: AyurvedaIngredientComputation
    let profileDistribution: AyurvedaDoshaDistribution?
    let target: AyurvedaDoshaDistribution?
    let summaryTitle: String
    let summarySubtitle: String?
    let accessibilityContext: String
    let usesPersonalizedEffectColors: Bool
    let onTap: (() -> Void)?

    init(
        computation: AyurvedaIngredientComputation,
        profileDistribution: AyurvedaDoshaDistribution?,
        target: AyurvedaDoshaDistribution?,
        summaryTitle: String = "Dosha Balance",
        summarySubtitle: String? = nil,
        accessibilityContext: String = "Daily Ayurveda",
        usesPersonalizedEffectColors: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.computation = computation
        self.profileDistribution = profileDistribution
        self.target = target
        self.summaryTitle = summaryTitle
        self.summarySubtitle = summarySubtitle
        self.accessibilityContext = accessibilityContext
        self.usesPersonalizedEffectColors = usesPersonalizedEffectColors
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .padding(.horizontal, 20)
        .accessibilityLabel(
            "\(accessibilityContext). Fit \(fitLabel)."
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(summaryTitle)
                    .font(.headline)

                Spacer(minLength: 8)

                GlassChipView(
                    label: "Fit: \(fitLabel)",
                    systemImage: fitIcon,
                    textColor: fitColor,
                    font: .subheadline,
                    fontWeight: .semibold,
                    horizontalPadding: 12,
                    verticalPadding: 7,
                    iconPlacement: .trailing
                )

                DoshaBalanceGlyph(
                    distribution: foodEffectDistribution
                )
                .frame(width: 44, height: 38)
            }

            if let computed = computation.computed {
                VStack(spacing: 8) {
                    doshaScale(
                        dosha: .vata,
                        value: computed.vata,
                        profileWeight: profileDistribution?.vata ?? 0
                    )
                    doshaScale(
                        dosha: .pitta,
                        value: computed.pitta,
                        profileWeight: profileDistribution?.pitta ?? 0
                    )
                    doshaScale(
                        dosha: .kapha,
                        value: computed.kapha,
                        profileWeight: profileDistribution?.kapha ?? 0
                    )
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

            if let summarySubtitle {
                Text(summarySubtitle)
                    .font(.caption2)
                    .foregroundStyle(
                        effectManager.currentGlobalAccentColor.opacity(0.68)
                    )
            }
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private func doshaScale(
        dosha: AyurvedaDosha,
        value: Int,
        profileWeight: Double
    ) -> some View {
        let clampedValue = min(2, max(-2, value))
        let progress = CGFloat(2 - clampedValue) / 4
        let prefersPacifying = usesPersonalizedEffectColors
            ? prefersPacifyingEffect(for: profileWeight)
            : true
        let effectColor = personalizedColor(
            for: clampedValue,
            prefersPacifying: prefersPacifying
        )
        return HStack(alignment: .top, spacing: 12) {
            DoshaIdentityLabel(
                dosha: dosha,
                titleFont: .caption.weight(.semibold)
            )
            .frame(width: 88, alignment: .leading)

            VStack(spacing: 3) {
                doshaTrack(
                    progress: progress,
                    color: effectColor,
                    prefersPacifying: prefersPacifying
                )

                doshaScaleLabels(
                    selectedValue: clampedValue,
                    selectedColor: effectColor
                )
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(dosha.displayName) effect \(signedValue(clampedValue))"
        )
    }

    private func doshaTrack(
        progress: CGFloat,
        color: Color,
        prefersPacifying: Bool
    ) -> some View {
        let gradientColors = prefersPacifying
            ? [
                Color("AyurvedaAggravate"),
                neutralColor,
                Color("AyurvedaPacify"),
            ]
            : [
                Color("AyurvedaPacify"),
                neutralColor,
                Color("AyurvedaAggravate"),
            ]
        return GeometryReader { proxy in
            let markerDiameter: CGFloat = 12
            let trackInset = markerDiameter / 2
            let trackWidth = max(proxy.size.width - markerDiameter, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                ForEach(1..<4, id: \.self) { division in
                    Rectangle()
                        .fill(
                            effectManager.contrastingSurfaceColor.opacity(
                                division == 2 ? 0.72 : 0.5
                            )
                        )
                        .frame(
                            width: division == 2 ? 2 : 1,
                            height: division == 2 ? 10 : 8
                        )
                        .position(
                            x: trackInset
                                + trackWidth * CGFloat(division) / 4,
                            y: proxy.size.height / 2
                        )
                }

                Circle()
                    .fill(color)
                    .frame(width: markerDiameter, height: markerDiameter)
                    .overlay {
                        Circle()
                            .stroke(
                                effectManager.contrastingSurfaceColor
                                    .opacity(0.85),
                                lineWidth: 2
                            )
                    }
                    .position(
                        x: trackInset + trackWidth * progress,
                        y: proxy.size.height / 2
                    )
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func doshaScaleLabels(
        selectedValue: Int,
        selectedColor: Color
    ) -> some View {
        GeometryReader { proxy in
            let trackInset: CGFloat = 6
            let trackWidth = max(proxy.size.width - (trackInset * 2), 1)
            ForEach(
                Array(Self.scaleValues.enumerated()),
                id: \.offset
            ) { index, candidate in
                Text(signedValue(candidate))
                    .font(
                        .caption2.monospacedDigit().weight(
                            candidate == selectedValue ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(
                        candidate == selectedValue
                            ? selectedColor
                            : effectManager.currentGlobalAccentColor.opacity(0.62)
                    )
                    .position(
                        x: trackInset
                            + trackWidth * CGFloat(index) / 4,
                        y: 6
                    )
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func signedValue(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func prefersPacifyingEffect(for profileWeight: Double) -> Bool {
        guard profileDistribution != nil else { return true }
        return profileWeight >= (1.0 / 3.0)
    }

    private func personalizedColor(
        for value: Int,
        prefersPacifying: Bool
    ) -> Color {
        guard value != 0 else { return neutralColor }
        let isSupportive = prefersPacifying ? value < 0 : value > 0
        return isSupportive
            ? Color("AyurvedaPacify")
            : Color("AyurvedaAggravate")
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

    private var foodEffectDistribution: AyurvedaDoshaDistribution? {
        guard let computed = computation.computed else { return nil }
        let percentages = AyurvedaDisplayMath.percentages(
            vata: computed.vata,
            pitta: computed.pitta,
            kapha: computed.kapha
        )
        return AyurvedaDoshaDistribution(
            vata: Double(percentages.v),
            pitta: Double(percentages.p),
            kapha: Double(percentages.k)
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

private struct DoshaBalanceGlyph: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let distribution: AyurvedaDoshaDistribution?

    var body: some View {
        Canvas { context, size in
            let nodeRadius: CGFloat = 3.5
            let top = CGPoint(x: size.width / 2, y: nodeRadius + 1)
            let leading = CGPoint(
                x: nodeRadius + 1,
                y: size.height - nodeRadius - 1
            )
            let trailing = CGPoint(
                x: size.width - nodeRadius - 1,
                y: size.height - nodeRadius - 1
            )

            var triangle = Path()
            triangle.move(to: top)
            triangle.addLine(to: leading)
            triangle.addLine(to: trailing)
            triangle.closeSubpath()
            context.stroke(
                triangle,
                with: .color(
                    effectManager.currentGlobalAccentColor.opacity(0.55)
                ),
                lineWidth: 1.5
            )

            drawNode(at: top, color: .blue, in: &context)
            drawNode(at: leading, color: .orange, in: &context)
            drawNode(at: trailing, color: .green, in: &context)

            if distribution != nil {
                let centroid = CGPoint(
                    x: (top.x + leading.x + trailing.x) / 3,
                    y: (top.y + leading.y + trailing.y) / 3
                )
                let markerTop = insetPoint(top, toward: centroid)
                let markerLeading = insetPoint(leading, toward: centroid)
                let markerTrailing = insetPoint(trailing, toward: centroid)
                let weights = normalizedWeights
                let marker = CGPoint(
                    x: (markerTop.x * weights.vata)
                        + (markerLeading.x * weights.pitta)
                        + (markerTrailing.x * weights.kapha),
                    y: (markerTop.y * weights.vata)
                        + (markerLeading.y * weights.pitta)
                        + (markerTrailing.y * weights.kapha)
                )
                let haloRect = CGRect(
                    x: marker.x - 6,
                    y: marker.y - 6,
                    width: 12,
                    height: 12
                )
                let markerRect = CGRect(
                    x: marker.x - 4,
                    y: marker.y - 4,
                    width: 8,
                    height: 8
                )
                context.fill(
                    Path(ellipseIn: haloRect),
                    with: .color(markerHaloColor)
                )
                context.stroke(
                    Path(ellipseIn: haloRect),
                    with: .color(
                        effectManager.currentGlobalAccentColor.opacity(0.5)
                    ),
                    lineWidth: 1
                )
                context.fill(
                    Path(ellipseIn: markerRect),
                    with: .color(markerColor)
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var normalizedWeights: (vata: CGFloat, pitta: CGFloat, kapha: CGFloat) {
        guard let distribution else {
            return (1 / 3, 1 / 3, 1 / 3)
        }
        let total = distribution.vata + distribution.pitta + distribution.kapha
        guard total > 0 else { return (1 / 3, 1 / 3, 1 / 3) }
        return (
            CGFloat(distribution.vata / total),
            CGFloat(distribution.pitta / total),
            CGFloat(distribution.kapha / total)
        )
    }

    private var markerColor: Color {
        guard let distribution else {
            return effectManager.currentGlobalAccentColor
        }
        if distribution.vata >= distribution.pitta,
           distribution.vata >= distribution.kapha {
            return .blue
        }
        if distribution.pitta >= distribution.kapha {
            return .orange
        }
        return .green
    }

    private var markerHaloColor: Color {
        effectManager.contrastingSurfaceColor
    }

    private func insetPoint(
        _ point: CGPoint,
        toward centroid: CGPoint
    ) -> CGPoint {
        let insetFraction: CGFloat = 0.18
        return CGPoint(
            x: point.x + ((centroid.x - point.x) * insetFraction),
            y: point.y + ((centroid.y - point.y) * insetFraction)
        )
    }

    private func drawNode(
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
        context.fill(
            Path(ellipseIn: rect),
            with: .color(effectManager.contrastingSurfaceColor)
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(color),
            lineWidth: 1.5
        )
    }
}

struct DailyAyurvedaDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var selectedMealID: UUID?

    private static let mealPalette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red,
        Color(hex: "#00ffff"),
    ]

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
            Text("Daily Ayurveda")
                .font(.headline)
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
            if let computed = selected.computed {
                Text(selectedTitle)
                    .font(.title.weight(.bold))

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
                        Label(
                            "Fit: \(fitLabel(fit.direction))",
                            systemImage: fitIcon(fit.direction)
                        )
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(fitColor(fit.direction))
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
            } else {
                VStack(spacing: 16) {
                    Image(
                        systemName: selected.hasIngredients
                            ? "leaf.circle"
                            : "fork.knife.circle"
                    )
                    .font(.system(size: 52, weight: .medium))
                    .opacity(0.62)

                    Text(
                        selected.hasIngredients
                            ? "Not Enough Ayurveda Data"
                            : "No Foods to Display"
                    )
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                    if selected.hasIngredients {
                        Text(
                            "At least half of the food weight needs Ayurveda data."
                        )
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .opacity(0.76)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .accessibilityElement(children: .combine)
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
                        color: mealColors[meal.id]
                            ?? effectManager.currentGlobalAccentColor,
                        mealID: meal.id
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func scopeChip(
        title: String,
        color: Color,
        mealID: UUID?
    ) -> some View {
        let isSelected = selectedMealID == mealID
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedMealID = isSelected ? nil : mealID
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(color.opacity(isSelected ? 0.8 : 0.3))
                }
                .glassCardStyle(cornerRadius: 20)
                .overlay {
                    Capsule()
                        .stroke(color, lineWidth: isSelected ? 2 : 0)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var mealColors: [UUID: Color] {
        let sortedMeals = meals.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
        let paletteCount = Self.mealPalette.count
        return Dictionary(uniqueKeysWithValues:
            sortedMeals.enumerated().map { index, meal in
                (meal.id, Self.mealPalette[index % paletteCount])
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

    private func fitIcon(
        _ direction: AyurvedaFoodFitPresentation.Direction
    ) -> String {
        switch direction {
        case .supportive: "leaf.fill"
        case .mixed: "equal.circle.fill"
        case .lessSupportive: "arrow.down.right.circle.fill"
        }
    }

    private func fitLabel(
        _ direction: AyurvedaFoodFitPresentation.Direction
    ) -> String {
        switch direction {
        case .supportive: "Good"
        case .mixed: "Mixed"
        case .lessSupportive: "Poor"
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

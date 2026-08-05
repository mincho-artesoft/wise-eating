import SwiftUI

extension ExerciseItem {
    var hasExercisePracticeMetadata: Bool {
        family != nil
            || level != nil
            || breath != nil
            || drishti != nil
            || (durationSeconds ?? 0) > 0
    }

    var hasAyurvedaMetadata: Bool { dosha != nil }

    var hasYogaPracticeMetadata: Bool {
        hasExercisePracticeMetadata || hasAyurvedaMetadata
    }
}

struct YogaWorkoutExerciseEntry: Identifiable {
    let exercise: ExerciseItem
    let durationSeconds: Double

    var id: UUID { exercise.id }
}

struct ExerciseAyurvedaSearchResultChips: View {
    let item: ExerciseItem

    @ViewBuilder
    var body: some View {
        if let dosha = item.resolvedYogaDosha {
            AyurvedaDoshaResultChips(
                vata: dosha.vata,
                pitta: dosha.pitta,
                kapha: dosha.kapha,
                colorMode: .rawEffect
            )
        }
    }
}

struct ExercisePracticeEditorFields<FocusField: Hashable>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var family: AsanaFamily?
    @Binding var level: String
    @Binding var breath: YogaBreath?
    @Binding var drishti: YogaDrishti?

    let expandedPicker: ExercisePracticePicker?
    let onOpenPicker: (ExercisePracticePicker) -> Void
    @FocusState.Binding var focusedField: FocusField?
    let levelFocusField: FocusField

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            familyField

            StyledLabeledPicker(label: "Level") {
                ConfigurableTextField(
                    title: "1–3",
                    value: $level,
                    type: .integer,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: levelFocusField
                )
                .font(.system(size: 16))
            }
            .id(levelFocusField)

            breathField
            drishtiField
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }

    private var familySelection: Binding<Set<AsanaFamily.ID>> {
        Binding(
            get: { family.map { [$0.id] } ?? [] },
            set: { selectedIDs in
                family = AsanaFamily.allCases.first {
                    selectedIDs.contains($0.id)
                }
            }
        )
    }

    private var breathSelection: Binding<Set<YogaBreath.ID>> {
        Binding(
            get: { breath.map { [$0.id] } ?? [] },
            set: { selectedIDs in
                breath = YogaBreath.allCases.first {
                    selectedIDs.contains($0.id)
                }
            }
        )
    }

    private var drishtiSelection: Binding<Set<YogaDrishti.ID>> {
        Binding(
            get: { drishti.map { [$0.id] } ?? [] },
            set: { selectedIDs in
                drishti = YogaDrishti.allCases.first {
                    selectedIDs.contains($0.id)
                }
            }
        )
    }

    private var familyField: some View {
        searchablePickerField(
            label: "Family",
            selection: familySelection,
            items: AsanaFamily.allCases,
            itemLabel: { $0.rawValue },
            prompt: "Select a family",
            picker: .family
        )
    }

    private var breathField: some View {
        searchablePickerField(
            label: "Breath",
            selection: breathSelection,
            items: YogaBreath.allCases,
            itemLabel: { $0.rawValue },
            prompt: "Select a breathing option",
            picker: .breath
        )
    }

    private var drishtiField: some View {
        searchablePickerField(
            label: "Drishti (gaze)",
            selection: drishtiSelection,
            items: YogaDrishti.allCases,
            itemLabel: { $0.rawValue },
            prompt: "Select a gaze option",
            picker: .drishti
        )
    }

    private func searchablePickerField<Item: Identifiable & Hashable>(
        label: String,
        selection: Binding<Set<Item.ID>>,
        items: [Item],
        itemLabel: @escaping (Item) -> String,
        prompt: String,
        picker: ExercisePracticePicker
    ) -> some View {
        StyledLabeledPicker(label: label, isFixedHeight: false) {
            MultiSelectButton(
                selection: selection,
                items: items,
                label: itemLabel,
                prompt: prompt,
                isExpanded: expandedPicker == picker
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    onOpenPicker(picker)
                }
            }
        }
    }

}

enum ExercisePracticePicker: Hashable {
    case family
    case breath
    case drishti
}

struct SearchableSingleSelectList<Item: Identifiable & Hashable>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let items: [Item]
    let selection: Item?
    let label: (Item) -> String
    let searchPrompt: String
    let onSelect: (Item?) -> Void

    @State private var searchText = ""

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            label($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(
                        effectManager.currentGlobalAccentColor.opacity(0.7)
                    )
                TextField(
                    searchPrompt,
                    text: $searchText,
                    prompt: Text("Search...")
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.6)
                        )
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .padding()
            .glassCardStyle(cornerRadius: 25)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    selectionRow(
                        title: "Not set",
                        isSelected: selection == nil
                    ) {
                        onSelect(nil)
                    }

                    ForEach(filteredItems) { item in
                        selectionRow(
                            title: label(item),
                            isSelected: selection?.id == item.id
                        ) {
                            onSelect(item)
                        }
                    }

                    Spacer(minLength: 150)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal)
    }

    private func selectionRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .glassCardStyle(cornerRadius: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected
                            ? effectManager.currentGlobalAccentColor
                            : Color.clear,
                        lineWidth: 2
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseAyurvedaEditorSection: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var vata: Int
    @Binding var pitta: Int
    @Binding var kapha: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dosha Effects")
                .font(.caption.bold())

            DoshaScaleSelector(
                value: $vata,
                dosha: .vata,
                subtitle: "Movement & Air"
            )
            Divider()
            DoshaScaleSelector(
                value: $pitta,
                dosha: .pitta,
                subtitle: "Fire & Transformation"
            )
            Divider()
            DoshaScaleSelector(
                value: $kapha,
                dosha: .kapha,
                subtitle: "Structure & Water"
            )
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }
}

private struct ExercisePracticeMetric: Identifiable {
    let title: String
    let value: String
    let systemImage: String

    var id: String { title }
}

struct ExercisePracticeDetailSection: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let item: ExerciseItem

    private var hasContent: Bool {
        item.hasExercisePracticeMetadata
    }

    @ViewBuilder
    var body: some View {
        if hasContent {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            ForEach(Array(metricRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { metric in
                        metricView(metric)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }

    private var metrics: [ExercisePracticeMetric] {
        var values: [ExercisePracticeMetric] = []

        if let family = item.family?.rawValue {
            values.append(
                ExercisePracticeMetric(
                    title: "Family",
                    value: family,
                    systemImage: "figure.yoga"
                )
            )
        }
        if let level = formattedLevel {
            values.append(
                ExercisePracticeMetric(
                    title: "Level",
                    value: level,
                    systemImage: "chart.bar.fill"
                )
            )
        }
        if let duration = formattedDuration {
            values.append(
                ExercisePracticeMetric(
                    title: "Duration",
                    value: duration,
                    systemImage: "timer"
                )
            )
        }
        if let breath = item.breath?.rawValue {
            values.append(
                ExercisePracticeMetric(
                    title: "Breath",
                    value: breath,
                    systemImage: "wind"
                )
            )
        }
        if let drishti = item.drishti?.rawValue {
            values.append(
                ExercisePracticeMetric(
                    title: "Drishti",
                    value: drishti,
                    systemImage: "eye.fill"
                )
            )
        }

        return values
    }

    private var metricRows: [[ExercisePracticeMetric]] {
        guard metrics.count > 3 else { return [metrics] }
        return [Array(metrics.prefix(3)), Array(metrics.dropFirst(3))]
    }

    private var formattedLevel: String? {
        item.level.map { "Level \($0)" }
    }

    private var formattedDuration: String? {
        guard let seconds = item.durationSeconds, seconds > 0 else { return nil }
        return "\(seconds) sec"
    }

    private func metricView(_ metric: ExercisePracticeMetric) -> some View {
        VStack(spacing: 2) {
            Label {
                Text(metric.title)
            } icon: {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(Color("AyurvedaChipTint"))
            }
            .font(.caption)
            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)

            Text(metric.value)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
        }
    }

}

struct ExerciseAyurvedaDetailSection: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let item: ExerciseItem
    var usesCard = true

    @ViewBuilder
    var body: some View {
        if let dosha = item.dosha {
            let title = Text("Ayurveda")
                .font(.title2.weight(.semibold))

            let content = DoshaBarsView(
                vata: dosha.vata,
                pitta: dosha.pitta,
                kapha: dosha.kapha
            )

            if usesCard {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    content
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .tint(effectManager.currentGlobalAccentColor)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    title
                    content
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .tint(effectManager.currentGlobalAccentColor)
            }
        }
    }
}

struct YogaWorkoutAyurvedaEditorSection: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var isManualOverride: Bool
    @Binding var vata: Int
    @Binding var pitta: Int
    @Binding var kapha: Int

    let entries: [YogaWorkoutExerciseEntry]

    private var automaticDosha: YogaDosha? {
        YogaWorkoutAyurvedaMath.aggregate(
            entries.compactMap { entry in
                guard let dosha = entry.exercise.dosha else { return nil }
                return (dosha: dosha, durationSeconds: entry.durationSeconds)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ayurveda")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Set manually", isOn: $isManualOverride)
                    .onChange(of: isManualOverride) { wasManual, isManual in
                        guard isManual, !wasManual, let automaticDosha else { return }
                        vata = automaticDosha.vata
                        pitta = automaticDosha.pitta
                        kapha = automaticDosha.kapha
                    }

                if isManualOverride {
                    manualDoshaEditor
                } else {
                    automaticPreview
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }

    private var manualDoshaEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dosha Effects")
                .font(.caption.bold())

            DoshaScaleSelector(
                value: $vata,
                dosha: .vata,
                subtitle: "Movement & Air"
            )
            Divider()
            DoshaScaleSelector(
                value: $pitta,
                dosha: .pitta,
                subtitle: "Fire & Transformation"
            )
            Divider()
            DoshaScaleSelector(
                value: $kapha,
                dosha: .kapha,
                subtitle: "Structure & Water"
            )
        }
    }

    @ViewBuilder
    private var automaticPreview: some View {
        if let automaticDosha {
            Text("Calculated from the exercises — updates automatically")
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
            DoshaBarsView(
                vata: automaticDosha.vata,
                pitta: automaticDosha.pitta,
                kapha: automaticDosha.kapha
            )
        } else {
            Text("Add exercises with Ayurveda data to see a live preview.")
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
        }
    }
}

struct YogaWorkoutAyurvedaSection: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let entries: [YogaWorkoutExerciseEntry]
    var manualDosha: YogaDosha? = nil

    private var yogaEntries: [YogaWorkoutExerciseEntry] {
        entries.filter { $0.exercise.hasYogaPracticeMetadata }
    }

    private var automaticDosha: YogaDosha? {
        YogaWorkoutAyurvedaMath.aggregate(
            yogaEntries.compactMap { entry in
                guard let dosha = entry.exercise.dosha else { return nil }
                return (dosha: dosha, durationSeconds: entry.durationSeconds)
            }
        )
    }

    private var displayedDosha: YogaDosha? {
        manualDosha ?? automaticDosha
    }

    @ViewBuilder
    var body: some View {
        if !yogaEntries.isEmpty || manualDosha != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ayurveda")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        manualDosha == nil
                            ? "Calculated from \(yogaEntries.count) exercise\(yogaEntries.count == 1 ? "" : "s") in this workout."
                            : "Ayurveda effects set manually."
                    )
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))

                    if let displayedDosha {
                        DoshaBarsView(
                            vata: displayedDosha.vata,
                            pitta: displayedDosha.pitta,
                            kapha: displayedDosha.kapha
                        )
                    }
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .tint(effectManager.currentGlobalAccentColor)
        }
    }
}

import SwiftUI

extension ExerciseItem {
    var hasExercisePracticeMetadata: Bool {
        family != nil
            || level != nil
            || breath != nil
            || drishti != nil
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
                kapha: dosha.kapha
            )
        }
    }
}

struct ExercisePracticeEditorFields: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var family: AsanaFamily?
    @Binding var level: String
    @Binding var breath: YogaBreath?
    @Binding var drishti: YogaDrishti?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityGroup
            sectionDivider
            practiceGroup
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 12)
    }

    private var identityGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader("Pose Identity")

            StyledLabeledPicker(label: "Family") {
                Menu {
                    Button("Not set") {
                        family = nil
                    }

                    ForEach(AsanaFamily.allCases) { option in
                        Button(option.rawValue) {
                            family = option
                        }
                    }
                } label: {
                    HStack {
                        Text(family?.rawValue ?? "Select a family")
                            .foregroundStyle(
                                effectManager.currentGlobalAccentColor.opacity(
                                    family == nil ? 0.6 : 1
                                )
                            )
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }

            StyledLabeledPicker(label: "Level") {
                editorTextField(
                    "1–3",
                    text: $level,
                    keyboardType: .numberPad
                )
            }
        }
    }

    private var practiceGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader("Practice Guidance")

            StyledLabeledPicker(label: "Breath") {
                Menu {
                    Button("Not set") {
                        breath = nil
                    }
                    ForEach(YogaBreath.allCases) { option in
                        Button(option.rawValue) {
                            breath = option
                        }
                    }
                } label: {
                    optionMenuLabel(
                        breath?.rawValue ?? "Select a breathing option",
                        isEmpty: breath == nil
                    )
                }
            }

            StyledLabeledPicker(label: "Drishti (gaze)") {
                Menu {
                    Button("Not set") {
                        drishti = nil
                    }
                    ForEach(YogaDrishti.allCases) { option in
                        Button(option.rawValue) {
                            drishti = option
                        }
                    }
                } label: {
                    optionMenuLabel(
                        drishti?.rawValue ?? "Select a gaze option",
                        isEmpty: drishti == nil
                    )
                }
            }
        }
    }

    private func optionMenuLabel(_ text: String, isEmpty: Bool) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(
                    effectManager.currentGlobalAccentColor.opacity(isEmpty ? 0.6 : 1)
                )
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(effectManager.currentGlobalAccentColor)
    }

    private func editorTextField(
        _ prompt: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(prompt)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
        )
        .keyboardType(keyboardType)
        .textInputAutocapitalization(.sentences)
        .autocorrectionDisabled()
        .foregroundStyle(effectManager.currentGlobalAccentColor)
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
        VStack(alignment: .leading, spacing: 16) {
            identityContent
            practiceContent
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
    }

    @ViewBuilder
    private var identityContent: some View {
        let level = formattedLevel
        let values = [
            item.family?.rawValue,
            level,
            formattedDuration
        ].compactMap { $0 }

        if !values.isEmpty {
            propertyGroup(title: "Pose Identity", systemImage: "figure.yoga") {
                ChipGrid {
                    ForEach(values, id: \.self) { value in
                        GlassChipView(
                            label: value,
                            color: Color("AyurvedaChipTint"),
                            systemImage: nil,
                            textColor: effectManager.currentGlobalAccentColor,
                            isSelected: true,
                            action: nil
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var practiceContent: some View {
        let breath = item.breath?.rawValue
        let drishti = item.drishti?.rawValue

        if breath != nil || drishti != nil {
            propertyGroup(title: "Practice Guidance", systemImage: "wind") {
                VStack(alignment: .leading, spacing: 10) {
                    if let breath {
                        guidanceRow(
                            title: "Breath",
                            value: breath,
                            systemImage: "wind"
                        )
                    }
                    if let drishti {
                        guidanceRow(
                            title: "Drishti",
                            value: drishti,
                            systemImage: "eye.fill"
                        )
                    }
                }
            }
        }
    }

    private var formattedLevel: String? {
        item.level.map { "Level \($0)" }
    }

    private var formattedDuration: String? {
        guard let seconds = item.durationSeconds, seconds > 0 else { return nil }
        return "\(seconds) sec"
    }

    private func propertyGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
            content()
        }
    }

    private func guidanceRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(Color("AyurvedaPacify"))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            let content = VStack(alignment: .leading, spacing: 14) {
                Text("Ayurveda")
                    .font(.title2.weight(.semibold))
                DoshaBarsView(
                    vata: dosha.vata,
                    pitta: dosha.pitta,
                    kapha: dosha.kapha
                )
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .tint(effectManager.currentGlobalAccentColor)

            if usesCard {
                content
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
            } else {
                content
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Ayurveda")
                .font(.title2.weight(.semibold))

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
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
        .padding()
        .glassCardStyle(cornerRadius: 20)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Ayurveda")
                    .font(.title2.weight(.semibold))

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
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .tint(effectManager.currentGlobalAccentColor)
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
}

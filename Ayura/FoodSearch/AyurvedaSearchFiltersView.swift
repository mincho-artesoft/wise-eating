import SwiftUI

struct AyurvedaSearchFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var filters: AyurvedaSearchFilters

    private let rasaValues = [
        "sweet", "sour", "salty", "pungent", "bitter", "astringent",
    ]
    private let viryaValues = ["heating", "cooling", "neutral"]
    private let gunaValues = [
        "dense", "dry", "heavy", "light", "liquid", "oily", "penetrating",
        "rough", "sharp", "slimy", "smooth", "soft",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Dosha choices change ranking only. Foods that aggravate the selected dosha remain visible.")
                        .font(.footnote)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.72)
                        )
                }

                Section("Dosha effect") {
                    ForEach(AyurvedaSearchDosha.allCases) { dosha in
                        doshaRow(dosha)
                    }
                }

                Section {
                    chipFlow(
                        values: rasaValues,
                        selectedValues: filters.rasa,
                        tint: .green
                    ) { toggle($0, in: \.rasa) }
                } header: {
                    Text("Rasa · taste")
                } footer: {
                    Text("Multiple tastes are combined with OR.")
                }

                Section("Virya · energy") {
                    chipFlow(
                        values: viryaValues,
                        selectedValues: Set(filters.virya.map { [$0] } ?? []),
                        tint: .orange
                    ) { value in
                        filters.virya = filters.virya == value ? nil : value
                    }
                }

                Section("Digestion") {
                    Toggle(
                        "Easy on digestion",
                        isOn: $filters.easyOnDigestion
                    )
                    Text("Uses digestibility and agni effect together.")
                        .font(.caption)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor.opacity(0.72)
                        )
                }

                Section("Gunas · qualities") {
                    chipFlow(
                        values: gunaValues,
                        selectedValues: filters.gunas,
                        tint: .blue
                    ) { toggle($0, in: \.gunas) }
                }

            }
            .navigationTitle("Ayurvedic filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filters = .empty
                    }
                    .disabled(!filters.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .tint(effectManager.currentGlobalAccentColor)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }

    private func doshaRow(_ dosha: AyurvedaSearchDosha) -> some View {
        HStack {
            Text(dosha.displayName)
            Spacer()
            Menu {
                Button("Any effect") {
                    filters.set(nil, for: dosha)
                }
                Divider()
                ForEach(AyurvedaDoshaPreference.allCases) { preference in
                    Button {
                        filters.set(preference, for: dosha)
                    } label: {
                        if filters.preference(for: dosha) == preference {
                            Label(preference.displayName, systemImage: "checkmark")
                        } else {
                            Text(preference.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(
                        filters.preference(for: dosha)?.displayName
                            ?? "Any effect"
                    )
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(
                    filters.preference(for: dosha) == nil
                        ? effectManager.currentGlobalAccentColor.opacity(0.72)
                        : effectManager.currentGlobalAccentColor
                )
            }
        }
    }

    private func chipFlow(
        values: [String],
        selectedValues: Set<String>,
        tint: Color,
        action: @escaping (String) -> Void
    ) -> some View {
        CustomFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(values, id: \.self) { value in
                AyurvedaChip(
                    title: displayName(value),
                    systemImage: nil,
                    tint: tint,
                    isSelected: selectedValues.contains(value),
                    action: { action(value) }
                )
            }
        }
        .padding(.vertical, 3)
    }

    private func toggle(
        _ value: String,
        in keyPath: WritableKeyPath<AyurvedaSearchFilters, Set<String>>
    ) {
        if filters[keyPath: keyPath].contains(value) {
            filters[keyPath: keyPath].remove(value)
        } else {
            filters[keyPath: keyPath].insert(value)
        }
    }

    private func displayName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

struct AyurvedaSearchResultSummary: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let metadata: AyurvedaCanonicalSearchMetadata
    let filters: AyurvedaSearchFilters

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    valueChip(
                        "V \(signed(metadata.doshaVata))",
                        isEmphasized: filters.vata != nil
                    )
                    valueChip(
                        "P \(signed(metadata.doshaPitta))",
                        isEmphasized: filters.pitta != nil
                    )
                    valueChip(
                        "K \(signed(metadata.doshaKapha))",
                        isEmphasized: filters.kapha != nil
                    )
                    if let virya = metadata.virya {
                        valueChip(virya.capitalized, isEmphasized: filters.virya != nil)
                    }
                    if !metadata.rasa.isEmpty {
                        valueChip(
                            metadata.rasa.prefix(3).map(\.capitalized)
                                .joined(separator: " · "),
                            isEmphasized: !filters.rasa.isEmpty
                        )
                    }
                }
            }

            if let prabhava = metadata.prabhava,
               !prabhava.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label {
                    Text(prabhava)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.caption)
                .foregroundStyle(
                    effectManager.currentGlobalAccentColor.opacity(0.72)
                )
            }

            if let sourceCaption = metadata.sourceCaption {
                Label(sourceCaption, systemImage: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(
                        metadata.isInferred
                            ? Color.orange
                            : effectManager.currentGlobalAccentColor.opacity(0.72)
                    )
            }

            if metadata.confidenceAyur < 0.6 {
                Label(
                    "Lower-confidence Ayurvedic profile",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(.top, 3)
    }

    private func valueChip(
        _ text: String,
        isEmphasized: Bool
    ) -> some View {
        Text(text)
            .font(.caption2.weight(isEmphasized ? .semibold : .regular))
            .foregroundStyle(
                effectManager.currentGlobalAccentColor.opacity(
                    isEmphasized ? 1 : 0.72
                )
            )
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                effectManager.currentGlobalAccentColor.opacity(
                    isEmphasized ? 0.16 : 0.09
                ),
                in: Capsule()
            )
    }

    private func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(abs(value))" }
        return "0"
    }
}

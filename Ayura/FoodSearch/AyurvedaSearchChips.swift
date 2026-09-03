import SwiftUI

enum AyurvedaDoshaChipColorMode: Equatable {
    case personalized
    case rawEffect
}

struct AyurvedaDoshaQuickFilterChip: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let dosha: AyurvedaSearchDosha
    let preference: AyurvedaDoshaPreference?
    let action: () -> Void

    private var tint: Color {
        switch dosha {
        case .vata: return .blue
        case .pitta: return .orange
        case .kapha: return .green
        }
    }

    private var preferenceSymbol: String? {
        switch preference {
        case .pacifies: return "↓"
        case .neutral: return "0"
        case .aggravates: return "↑"
        case nil: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(dosha.displayName)
                if let preferenceSymbol {
                    Text(preferenceSymbol)
                        .font(.caption.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(0.6))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        preference == nil ? Color.clear : tint,
                        lineWidth: preference == nil ? 0 : 2
                    )
            }
        }
        .glassCardStyle(cornerRadius: 20)
        .buttonStyle(.plain)
        .accessibilityLabel(dosha.displayName)
        .accessibilityValue(preference?.displayName ?? "Not selected")
        .accessibilityHint(
            "Double tap to cycle through pacifies, neutral, aggravates, and off"
        )
    }
}

struct AyurvedaDoshaResultChips: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var profileDistribution: AyurvedaDoshaDistribution?

    private let vata: Int?
    private let pitta: Int?
    private let kapha: Int?
    private let showsUnavailableState: Bool
    private let colorMode: AyurvedaDoshaChipColorMode

    init(
        metadata: AyurvedaCanonicalSearchMetadata?,
        colorMode: AyurvedaDoshaChipColorMode = .personalized
    ) {
        _profileDistribution = State(initialValue: nil)
        vata = metadata?.doshaVata
        pitta = metadata?.doshaPitta
        kapha = metadata?.doshaKapha
        showsUnavailableState = metadata == nil
        self.colorMode = colorMode
    }

    init(
        vata: Int,
        pitta: Int,
        kapha: Int,
        colorMode: AyurvedaDoshaChipColorMode = .personalized
    ) {
        _profileDistribution = State(initialValue: nil)
        self.vata = vata
        self.pitta = pitta
        self.kapha = kapha
        showsUnavailableState = false
        self.colorMode = colorMode
    }

    var body: some View {
        Group {
            if showsUnavailableState {
                Text("Ayurvedic effects unavailable")
                    .font(.caption2)
                    .foregroundStyle(
                        effectManager.currentGlobalAccentColor.opacity(0.7)
                    )
            } else {
                CustomFlowLayout(horizontalSpacing: 6, verticalSpacing: 5) {
                    doshaChip(
                        "Vata",
                        value: vata,
                        profileWeight: profileDistribution?.vata
                    )
                    doshaChip(
                        "Pitta",
                        value: pitta,
                        profileWeight: profileDistribution?.pitta
                    )
                    doshaChip(
                        "Kapha",
                        value: kapha,
                        profileWeight: profileDistribution?.kapha
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ayurvedic dosha effects")
        .onAppear(perform: reloadProfileDistribution)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .ayurvedaConstitutionDidChange
            )
        ) { _ in
            reloadProfileDistribution()
        }
    }

    private func doshaChip(
        _ name: String,
        value: Int?,
        profileWeight: Double?
    ) -> some View {
        let presentation = value.map {
            AyurvedaDoshaEffectPresentation(value: $0)
        }
        let color = value
            .map {
                personalizedColor(
                    for: $0,
                    profileWeight: profileWeight
                )
            }
            ?? effectManager.currentGlobalAccentColor.opacity(0.7)

        return Text("\(name) \(presentation?.signedValue ?? "—")")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // The flow layout must measure each capsule at its natural width.
            // Otherwise HStack-style compression can wrap only "−1" inside
            // the capsule instead of moving the whole capsule to row two.
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel(
                presentation?.accessibilityLabel(dosha: name)
                    ?? "\(name): no Ayurvedic profile"
            )
            .accessibilityIdentifier(
                "ayurveda-dosha-chip-\(name.lowercased())"
            )
    }

    private func personalizedColor(
        for value: Int,
        profileWeight: Double?
    ) -> Color {
        guard value != 0 else { return Color("AyurvedaNeutral") }
        if colorMode == .rawEffect {
            return value < 0
                ? Color("AyurvedaPacify")
                : Color("AyurvedaAggravate")
        }
        let prefersPacifying = profileWeight.map {
            $0 >= (1.0 / 3.0)
        } ?? true
        let isSupportive = prefersPacifying ? value < 0 : value > 0
        return isSupportive
            ? Color("AyurvedaPacify")
            : Color("AyurvedaAggravate")
    }

    private func reloadProfileDistribution() {
        profileDistribution = AyurvedaConstitutionStore
            .activeRecord()?
            .result
            .distribution
    }
}

struct AyurvedaSearchedFieldChips: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let metadata: AyurvedaCanonicalSearchMetadata
    let fields: [AyurvedaSearchDisplayField]

    var body: some View {
        CustomFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(fields, id: \.self) { field in
                if let text = displayText(for: field) {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            effectManager.currentGlobalAccentColor.opacity(0.10),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    effectManager.currentGlobalAccentColor
                                        .opacity(0.35),
                                    lineWidth: 1
                                )
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Requested Ayurvedic properties")
    }

    private func displayText(
        for field: AyurvedaSearchDisplayField
    ) -> String? {
        switch field {
        case .rasa:
            return listText(label: "Rasa", values: metadata.rasa)
        case .virya:
            return optionalText(label: "Virya", value: metadata.virya)
        case .vipaka:
            return optionalText(label: "Vipaka", value: metadata.vipaka)
        case .guna:
            return listText(label: "Guna", values: metadata.gunas)
        case .agni:
            guard let value = metadata.agniEffect else { return nil }
            let effect = value > 0
                ? "Kindles"
                : (value < 0 ? "Dampens" : "Neutral")
            return "Agni: \(effect)"
        case .digestibility:
            guard let value = metadata.digestibility else { return nil }
            return "Digestibility: \(digestibilityLabel(value))"
        case .digestion:
            var values: [String] = []
            if let digestibility = metadata.digestibility {
                values.append(digestibilityLabel(digestibility))
            }
            if let agni = metadata.agniEffect {
                if agni > 0 {
                    values.append("Kindles agni")
                } else if agni < 0 {
                    values.append("Dampens agni")
                }
            }
            guard !values.isEmpty else { return nil }
            return "Digestion: \(values.joined(separator: " · "))"
        case .season:
            return listText(label: "Season", values: metadata.seasons)
        }
    }

    private func listText(
        label: String,
        values: [String]
    ) -> String? {
        guard !values.isEmpty else { return nil }
        return "\(label): \(values.map(displayName).joined(separator: " · "))"
    }

    private func optionalText(
        label: String,
        value: String?
    ) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return "\(label): \(displayName(value))"
    }

    private func digestibilityLabel(_ value: Int) -> String {
        if value >= 4 { return "Easy (\(value)/5)" }
        if value <= 2 { return "Heavy (\(value)/5)" }
        return "Moderate (\(value)/5)"
    }

    private func displayName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

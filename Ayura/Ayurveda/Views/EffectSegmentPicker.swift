import SwiftUI

enum EffectSegmentTone: Sendable {
  case cooling
  case neutral
  case heating
  case accent
}

struct EffectSegmentOption: Identifiable, Sendable {
  let value: String
  let title: String
  let systemImage: String?
  let tone: EffectSegmentTone

  var id: String { value }
}

struct EffectSegmentPicker: View {
  @ObservedObject private var effectManager = EffectManager.shared
  @Binding var selection: String?

  let title: String
  let options: [EffectSegmentOption]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options) { option in
        optionButton(option)
      }
    }
    .padding(3)
    .background(
      effectManager.currentGlobalAccentColor.opacity(
        effectManager.isLightRowTextColor ? 0.12 : 0.07
      ),
      in: Capsule()
    )
    .overlay {
      Capsule()
        .stroke(
          effectManager.currentGlobalAccentColor.opacity(
            effectManager.isLightRowTextColor ? 0.22 : 0.12
          )
        )
    }
    .foregroundStyle(effectManager.currentGlobalAccentColor)
    .tint(effectManager.currentGlobalAccentColor)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }

  private func optionButton(_ option: EffectSegmentOption) -> some View {
    let isSelected = selection == option.value
    let tint = color(for: option.tone)

    return Button {
      selection = isSelected ? nil : option.value
    } label: {
      HStack(spacing: 5) {
        if let systemImage = option.systemImage {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
        Text(option.title)
          .lineLimit(1)
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(
        isSelected ? tint : effectManager.currentGlobalAccentColor
      )
      .frame(maxWidth: .infinity, minHeight: 44)
      .background {
        if isSelected {
          Capsule()
            .fill(
              tint.opacity(
                effectManager.isLightRowTextColor ? 0.30 : 0.17
              )
            )
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(option.title)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint(isSelected ? "Double tap to clear" : "Double tap to select")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func color(for tone: EffectSegmentTone) -> Color {
    switch tone {
    case .cooling:
      return .blue
    case .neutral:
      return effectManager.currentGlobalAccentColor
    case .heating:
      return .orange
    case .accent:
      return effectManager.currentGlobalAccentColor
    }
  }
}

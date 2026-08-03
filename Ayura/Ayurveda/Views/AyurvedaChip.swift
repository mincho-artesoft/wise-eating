import SwiftUI

struct AyurvedaChip: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var effectManager = EffectManager.shared

  let title: String
  let systemImage: String?
  let tint: Color
  let isSelected: Bool
  let action: () -> Void
  let isReadOnly: Bool

  init(
    title: String,
    systemImage: String?,
    tint: Color,
    isSelected: Bool,
    action: @escaping () -> Void,
    isReadOnly: Bool = false
  ) {
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    self.isSelected = isSelected
    self.action = action
    self.isReadOnly = isReadOnly
  }

  @ViewBuilder
  var body: some View {
    if isReadOnly {
      readOnlyChip
    } else {
      editorChip
    }
  }

  private var editorChip: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if let systemImage {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
        Text(title)
          .lineLimit(1)
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .background {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .fill(.thinMaterial)
          .overlay {
            if isSelected {
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.28 : 0.16))
            }
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(
            isSelected
              ? tint.opacity(0.58)
              : effectManager.currentGlobalAccentColor.opacity(
                colorScheme == .dark ? 0.22 : 0.10
              ),
            lineWidth: 1
          )
      }
      .overlay(alignment: .topTrailing) {
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(
              effectManager.isLightRowTextColor ? Color.white : Color.black
            )
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .offset(x: 5, y: -5)
            .accessibilityHidden(true)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var readOnlyChip: some View {
    HStack(spacing: 7) {
      if let systemImage {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
      }
      Text(title)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(effectManager.currentGlobalAccentColor)
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .frame(minHeight: 34)
    .background {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.11))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(tint.opacity(colorScheme == .dark ? 0.50 : 0.32), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

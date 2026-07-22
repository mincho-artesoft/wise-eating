import SwiftUI

struct AyurvedaChip: View {
  @Environment(\.colorScheme) private var colorScheme

  let title: String
  let systemImage: String?
  let tint: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
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
      .foregroundStyle(isSelected ? tint : Color.primary)
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
              : Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.10),
            lineWidth: 1
          )
      }
      .overlay(alignment: .topTrailing) {
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
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
}

import SwiftUI

struct AyurvedaChipRow: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let title: String
  let values: [String]
  var color: Color?

  var body: some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.caption)
          .foregroundStyle(
            effectManager.currentGlobalAccentColor.opacity(0.72)
          )
        CustomFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
          ForEach(Array(values.enumerated()), id: \.offset) { _, value in
            AyurvedaFacetChip(
              text: value,
              color: color ?? effectManager.currentGlobalAccentColor
            )
          }
        }
      }
    }
  }
}

struct AyurvedaWarningsView: View {
  let viruddha: [String]
  let contraindications: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !viruddha.isEmpty {
        warningGroup(
          title: "Viruddha — incompatible combinations",
          values: viruddha,
          color: .orange
        )
      }
      if !contraindications.isEmpty {
        warningGroup(
          title: "Contraindications",
          values: contraindications,
          color: .red
        )
      }
    }
  }

  private func warningGroup(
    title: String,
    values: [String],
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
          Text(value)
            .font(.caption)
        }
        .foregroundStyle(color)
      }
    }
  }
}

private struct AyurvedaFacetChip: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      .background(color.opacity(0.2), in: Capsule())
  }
}

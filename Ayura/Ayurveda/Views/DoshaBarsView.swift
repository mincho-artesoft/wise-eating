import SwiftUI

struct DoshaBarsView: View {
  @ObservedObject private var effectManager = EffectManager.shared

  private enum Mode: String, CaseIterable, Identifiable {
    case signed = "±"
    case percentage = "%"

    var id: String { rawValue }
  }

  let vata: Int
  let pitta: Int
  let kapha: Int
  @State private var mode: Mode = .signed

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack {
          Text("Doshas")
            .font(.headline)
          Spacer(minLength: 12)
          modePicker
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Doshas")
            .font(.headline)
          modePicker
        }
      }

      if mode == .signed {
        signedBars
        legend
      } else {
        percentageBars
      }
    }
    .foregroundStyle(effectManager.currentGlobalAccentColor)
    .tint(effectManager.currentGlobalAccentColor)
  }

  private var modePicker: some View {
    WrappingSegmentedControl(
      selection: $mode,
      layoutMode: .wrap,
      selectionTint: { _ in effectManager.currentGlobalAccentColor }
    )
    .frame(width: 88)
    .padding(2)
    .accessibilityLabel("Dosha display")
  }

  private var signedBars: some View {
    VStack(spacing: 14) {
      DoshaScaleSelector(readOnlyValue: vata, dosha: .vata)
      DoshaScaleSelector(readOnlyValue: pitta, dosha: .pitta)
      DoshaScaleSelector(readOnlyValue: kapha, dosha: .kapha)
    }
  }

  private var legend: some View {
    ChipGrid {
      DoshaLegendItem(
        title: "Pacifies",
        detail: "(calms, reduces)",
        color: Color("AyurvedaPacify")
      )
      DoshaLegendItem(
        title: "Neutral",
        detail: "(no effect)",
        color: Color("AyurvedaNeutral")
      )
      DoshaLegendItem(
        title: "Aggravates",
        detail: "(increases)",
        color: Color("AyurvedaAggravate")
      )
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Dosha effect legend")
  }

  private var percentageBars: some View {
    let percentages = AyurvedaDisplayMath.percentages(
      vata: vata,
      pitta: pitta,
      kapha: kapha
    )
    return VStack(alignment: .leading, spacing: 8) {
      DoshaPercentageBar(
        values: [
          .init(label: "Vata", value: percentages.v, color: .blue),
          .init(label: "Pitta", value: percentages.p, color: .orange),
          .init(label: "Kapha", value: percentages.k, color: .green)
        ]
      )
    }
  }
}

private struct DoshaLegendItem: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let title: String
  let detail: String
  let color: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(title)
        .fontWeight(.semibold)
        .foregroundStyle(color)
      Text(detail)
        .foregroundStyle(
          effectManager.currentGlobalAccentColor.opacity(0.72)
        )
    }
    .font(.caption)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }
}

private struct DoshaPercentageValue: Identifiable {
  let label: String
  let value: Int
  let color: Color

  var id: String { label }
}

private struct DoshaPercentageBar: View {
  let values: [DoshaPercentageValue]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 0) {
          ForEach(values.filter { $0.value > 0 }) { item in
            item.color
              .frame(width: proxy.size.width * Double(item.value) / 100.0)
          }
        }
        .clipShape(Capsule())
      }
      .frame(height: 12)

      ChipGrid {
        ForEach(values) { item in
          HStack(spacing: 4) {
            Circle()
              .fill(item.color)
              .frame(width: 8, height: 8)
            Text("\(item.label) \(item.value)%")
              .font(.caption)
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}

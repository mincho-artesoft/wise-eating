import SwiftUI

struct DoshaBarsView: View {
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
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Doshas")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Picker("Dosha display", selection: $mode) {
          ForEach(Mode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 88)
      }

      if mode == .signed {
        signedBars
      } else {
        percentageBars
      }
    }
  }

  private var signedBars: some View {
    VStack(spacing: 10) {
      DoshaBarRowView(name: "Vata", value: vata)
      DoshaBarRowView(name: "Pitta", value: pitta)
      DoshaBarRowView(name: "Kapha", value: kapha)
    }
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
          .init(label: "Vata", value: percentages.v, color: Color(hex: "8E7CC3")),
          .init(label: "Pitta", value: percentages.p, color: Color(hex: "E06666")),
          .init(label: "Kapha", value: percentages.k, color: Color(hex: "6AA84F"))
        ]
      )
    }
  }
}

struct DoshaBarRowView: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let name: String
  let value: Int

  var body: some View {
    HStack(spacing: 8) {
      Text(name)
        .frame(width: 56, alignment: .leading)
      signedTrack
      Text(valueText)
        .frame(width: 132, alignment: .trailing)
        .font(.caption)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(valueText)")
  }

  private var valueText: String {
    AyurvedaDisplayMath.valueString(value)
      + " "
      + AyurvedaDisplayMath.effectLabel(value)
  }

  private var signedTrack: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let midpoint = width / 2
      let fillWidth = midpoint * AyurvedaDisplayMath.barFraction(value)
      ZStack(alignment: .leading) {
        Capsule()
          .fill(effectManager.currentGlobalAccentColor.opacity(0.12))
        Rectangle()
          .fill(effectManager.currentGlobalAccentColor.opacity(0.4))
          .frame(width: 1, height: 12)
          .offset(x: midpoint - 0.5)
        if value < 0 {
          Capsule()
            .fill(Color(hex: "34A853"))
            .frame(width: fillWidth, height: 12)
            .offset(x: midpoint - fillWidth)
        } else if value > 0 {
          Capsule()
            .fill(Color(hex: "E8710A"))
            .frame(width: fillWidth, height: 12)
            .offset(x: midpoint)
        }
      }
      .clipShape(Capsule())
    }
    .frame(height: 12)
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

      HStack(spacing: 14) {
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

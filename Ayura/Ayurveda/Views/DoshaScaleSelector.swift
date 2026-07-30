import SwiftUI
import UIKit

struct DoshaScaleSelector: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var value: Int

  let name: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  let isReadOnly: Bool

  private let values = [-2, -1, 0, 1, 2]

  init(
    value: Binding<Int>,
    name: String,
    subtitle: String,
    systemImage: String,
    tint: Color
  ) {
    _value = value
    self.name = name
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    isReadOnly = false
  }

  init(readOnlyValue value: Int, name: String) {
    _value = .constant(min(2, max(-2, value)))
    self.name = name
    subtitle = ""
    systemImage = ""
    tint = .clear
    isReadOnly = true
  }

  @ViewBuilder
  var body: some View {
    if isReadOnly {
      readOnlyBody
    } else {
      editorBody
    }
  }

  private var editorBody: some View {
    VStack(alignment: .leading, spacing: 6) {
      identity
      scale
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name) effect")
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Adjusts dosha effect")
    .accessibilityAdjustableAction(adjustValue)
  }

  private var readOnlyBody: some View {
    let presentation = AyurvedaDoshaEffectPresentation(value: value)
    return ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 12) {
        Text(name)
          .font(.headline)
          .frame(minWidth: 56, alignment: .leading)
        readOnlyEffect(presentation)
          .frame(width: 200, alignment: .leading)
        readOnlyScale(presentation)
          .frame(minWidth: 240)
      }

      VStack(alignment: .leading, spacing: 9) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
              .font(.headline)
            Spacer(minLength: 8)
            readOnlyEffect(presentation)
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(name)
              .font(.headline)
            readOnlyEffect(presentation)
          }
        }
        readOnlyScale(presentation)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel(dosha: name))
  }

  private func readOnlyEffect(
    _ presentation: AyurvedaDoshaEffectPresentation
  ) -> some View {
    HStack(spacing: 6) {
      Image(systemName: presentation.systemImage)
        .accessibilityHidden(true)
      Text(presentation.primaryText)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(readOnlyColor(presentation.tone))
  }

  private func readOnlyScale(
    _ presentation: AyurvedaDoshaEffectPresentation
  ) -> some View {
    VStack(spacing: 4) {
      HStack(spacing: 0) {
        ForEach(values, id: \.self) { candidate in
          Text(displayValue(candidate))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }

      GeometryReader { proxy in
        let width = max(proxy.size.width, 16)
        let trackInset: CGFloat = 8
        let trackWidth = max(width - (trackInset * 2), 1)
        let midpoint = trackInset + trackWidth / 2
        let dotX = trackInset
          + trackWidth * CGFloat(min(2, max(-2, value)) + 2) / 4
        let fillWidth = abs(dotX - midpoint)

        ZStack {
          Capsule()
            .fill(Color("AyurvedaNeutral").opacity(colorScheme == .dark ? 0.34 : 0.22))
            .frame(width: trackWidth, height: 5)
            .position(x: width / 2, y: 10)

          if value != 0 {
            Capsule()
              .fill(readOnlyColor(presentation.tone).opacity(
                colorScheme == .dark ? 0.72 : 0.58
              ))
              .frame(width: fillWidth, height: 7)
              .position(x: (midpoint + dotX) / 2, y: 10)
          }

          ForEach(values, id: \.self) { candidate in
            let tickX = trackInset + trackWidth * CGFloat(candidate + 2) / 4
            Rectangle()
              .fill(Color("AyurvedaNeutral").opacity(candidate == 0 ? 0.78 : 0.48))
              .frame(width: candidate == 0 ? 2 : 1, height: candidate == 0 ? 16 : 11)
              .position(x: tickX, y: 10)
          }

          Circle()
            .fill(readOnlyColor(presentation.tone))
            .frame(width: 16, height: 16)
            .overlay {
              Circle()
                .stroke(Color(.systemBackground).opacity(0.88), lineWidth: 2)
            }
            .position(x: dotX, y: 10)
        }
      }
      .frame(height: 20)

      HStack {
        Label("Pacifies", systemImage: "leaf.fill")
          .foregroundStyle(Color("AyurvedaPacify"))
        Spacer(minLength: 8)
        Label("Aggravates", systemImage: "sun.max.fill")
          .foregroundStyle(Color("AyurvedaAggravate"))
      }
      .font(.caption2)
      .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityHidden(true)
  }

  private func readOnlyColor(_ tone: AyurvedaDoshaTone) -> Color {
    switch tone {
    case .pacify:
      return Color("AyurvedaPacify")
    case .neutral:
      return Color("AyurvedaNeutral")
    case .aggravate:
      return Color("AyurvedaAggravate")
    }
  }

  private var identity: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.14), in: Circle())
        .overlay {
          Circle()
            .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.body)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var scale: some View {
    VStack(spacing: 2) {
      HStack(spacing: 0) {
        ForEach(values, id: \.self) { candidate in
          segment(candidate)
        }
      }
      .padding(2)
      .background(.thinMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12))
      }

      selectionIndicator
    }
  }

  private var selectionIndicator: some View {
    GeometryReader { proxy in
      let selectedIndex = CGFloat(min(2, max(-2, value)) + 2)
      let segmentWidth = proxy.size.width / CGFloat(values.count)
      let indicatorX = segmentWidth * (selectedIndex + 0.5)
      let labelWidth = min(CGFloat(110), proxy.size.width)
      let labelX = min(
        max(indicatorX, labelWidth / 2),
        proxy.size.width - labelWidth / 2
      )

      ZStack(alignment: .topLeading) {
        Image(systemName: "triangle.fill")
          .font(.system(size: 6))
          .position(x: indicatorX, y: 3)

        Text(stateWord)
          .font(.caption2.weight(.medium))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(width: labelWidth)
          .position(x: labelX, y: 14)
      }
      .foregroundStyle(stateColor)
    }
    .frame(height: 22)
  }

  private func segment(_ candidate: Int) -> some View {
    Button {
      setValue(candidate)
    } label: {
      Text(displayValue(candidate))
        .font(.caption.monospacedDigit())
        .foregroundStyle(segmentColor(candidate))
        .frame(maxWidth: .infinity, minHeight: 32)
        .background {
          if candidate == value {
            Capsule()
              .fill(stateColor.opacity(colorScheme == .dark ? 0.32 : 0.18))
          }
        }
    }
    .buttonStyle(.plain)
  }

  private var stateColor: Color {
    if value < 0 { return .green }
    if value > 0 { return .orange }
    return .blue
  }

  private var stateWord: String {
    if value < 0 { return "pacifying" }
    if value > 0 { return "aggravating" }
    return "neutral"
  }

  private func segmentColor(_ candidate: Int) -> Color {
    if candidate < 0 { return .green }
    if candidate > 0 { return .orange }
    return .primary
  }

  private func displayValue(_ candidate: Int) -> String {
    if candidate < 0 { return "−\(abs(candidate))" }
    if candidate > 0 { return "+\(candidate)" }
    return "0"
  }

  private var accessibilityValue: String {
    let spokenNumber: String
    switch value {
    case -2: spokenNumber = "minus two"
    case -1: spokenNumber = "minus one"
    case 1: spokenNumber = "plus one"
    case 2: spokenNumber = "plus two"
    default: spokenNumber = "zero"
    }
    return "\(spokenNumber), \(AyurvedaDisplayMath.effectLabel(value))"
  }

  private func setValue(_ newValue: Int) {
    guard newValue != value else { return }
    value = min(max(newValue, -2), 2)
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.prepare()
    generator.impactOccurred()
  }

  private func adjustValue(_ direction: AccessibilityAdjustmentDirection) {
    switch direction {
    case .increment:
      setValue(min(value + 1, 2))
    case .decrement:
      setValue(max(value - 1, -2))
    @unknown default:
      break
    }
  }
}

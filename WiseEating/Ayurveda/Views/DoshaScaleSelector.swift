import SwiftUI
import UIKit

struct DoshaScaleSelector: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var value: Int

  let name: String
  let subtitle: String
  let systemImage: String
  let tint: Color

  private let values = [-2, -1, 0, 1, 2]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      identity
      scale
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name) effect")
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Adjusts dosha effect")
    .accessibilityAdjustableAction(adjustValue)
  }

  private var identity: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(tint)
        .frame(width: 48, height: 48)
        .background(tint.opacity(0.14), in: Circle())
        .overlay {
          Circle()
            .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.headline)
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
      .padding(3)
      .background(.thinMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12))
      }

      HStack(spacing: 0) {
        ForEach(values, id: \.self) { candidate in
          if candidate == value {
            VStack(spacing: 0) {
              Image(systemName: "triangle.fill")
                .font(.system(size: 7))
              Text(stateWord)
                .font(.caption2.weight(.medium))
            }
            .foregroundStyle(stateColor)
            .frame(maxWidth: .infinity, minHeight: 26)
          } else {
            Color.clear
              .frame(maxWidth: .infinity, minHeight: 26)
          }
        }
      }
    }
  }

  private func segment(_ candidate: Int) -> some View {
    Button {
      setValue(candidate)
    } label: {
      Text(displayValue(candidate))
        .font(.body.monospacedDigit())
        .foregroundStyle(segmentColor(candidate))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
          if candidate == value {
            Capsule()
              .fill(stateColor.opacity(colorScheme == .dark ? 0.32 : 0.18))
          }
        }
    }
    .buttonStyle(.plain)
  }

  private var caption: String {
    "\(displayValue(value)) · \(AyurvedaDisplayMath.effectLabel(value))"
  }

  private var stateWord: String {
    if value < 0 { return "pacifying" }
    if value > 0 { return "aggravating" }
    return "neutral"
  }

  private var stateColor: Color {
    if value < 0 { return .green }
    if value > 0 { return .orange }
    return .blue
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

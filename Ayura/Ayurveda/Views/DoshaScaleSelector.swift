import SwiftUI
import UIKit

struct DoshaScaleSelector: View {
  @ObservedObject private var effectManager = EffectManager.shared
  @Binding var value: Int
  @State private var profileDistribution: AyurvedaDoshaDistribution?

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
    _profileDistribution = State(initialValue: nil)
    self.name = name
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    isReadOnly = false
  }

  init(readOnlyValue value: Int, name: String) {
    _value = .constant(min(2, max(-2, value)))
    _profileDistribution = State(initialValue: nil)
    self.name = name
    subtitle = ""
    systemImage = ""
    tint = .clear
    isReadOnly = true
  }

  @ViewBuilder
  var body: some View {
    Group {
      if isReadOnly {
        readOnlyBody
      } else {
        editorBody
      }
    }
    .foregroundStyle(effectManager.currentGlobalAccentColor)
    .tint(effectManager.currentGlobalAccentColor)
    .onAppear(perform: reloadProfileDistribution)
    .onReceive(
      NotificationCenter.default.publisher(
        for: .ayurvedaConstitutionDidChange
      )
    ) { _ in
      reloadProfileDistribution()
    }
  }

  private var editorBody: some View {
    VStack(alignment: .leading, spacing: 6) {
      identity
      profileAwareScale(isInteractive: true)
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
    .foregroundStyle(stateColor)
  }

  private func readOnlyScale(
    _: AyurvedaDoshaEffectPresentation
  ) -> some View {
    profileAwareScale(isInteractive: false)
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
          .foregroundStyle(
            effectManager.currentGlobalAccentColor.opacity(0.72)
          )
      }
    }
  }

  private func profileAwareScale(isInteractive: Bool) -> some View {
    VStack(spacing: 3) {
      GeometryReader { proxy in
        let markerDiameter: CGFloat = 12
        let trackInset = markerDiameter / 2
        let trackWidth = max(proxy.size.width - markerDiameter, 1)
        let progress = CGFloat(min(2, max(-2, value)) + 2) / 4

        ZStack {
          Capsule()
            .fill(
              LinearGradient(
                colors: gradientColors,
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(height: 8)

          ForEach(1..<4, id: \.self) { division in
            Rectangle()
              .fill(.white.opacity(division == 2 ? 0.72 : 0.5))
              .frame(
                width: division == 2 ? 2 : 1,
                height: division == 2 ? 10 : 8
              )
              .position(
                x: trackInset + trackWidth * CGFloat(division) / 4,
                y: proxy.size.height / 2
              )
          }

          Circle()
            .fill(stateColor)
            .frame(width: markerDiameter, height: markerDiameter)
            .overlay {
              Circle()
                .stroke(Color(.systemBackground).opacity(0.88), lineWidth: 2)
            }
            .position(
              x: trackInset + trackWidth * progress,
              y: proxy.size.height / 2
            )

          if isInteractive {
            Color.clear
              .contentShape(Rectangle())
              .gesture(
                DragGesture(minimumDistance: 0)
                  .onEnded { gesture in
                    setValue(
                      scaleValue(
                        at: gesture.location.x,
                        width: proxy.size.width
                      )
                    )
                  }
              )
          }
        }
      }
      .frame(height: 16)

      scaleLabels
    }
    .accessibilityHidden(true)
  }

  private var scaleLabels: some View {
    GeometryReader { proxy in
      let trackInset: CGFloat = 6
      let trackWidth = max(proxy.size.width - (trackInset * 2), 1)
      ForEach(Array(values.enumerated()), id: \.offset) { index, candidate in
        Text(displayValue(candidate))
          .font(
            .caption2.monospacedDigit().weight(
              candidate == value ? .semibold : .regular
            )
          )
          .foregroundStyle(
            candidate == value
              ? stateColor
              : effectManager.currentGlobalAccentColor.opacity(0.62)
          )
          .position(
            x: trackInset + trackWidth * CGFloat(index) / 4,
            y: 6
          )
      }
    }
    .frame(height: 12)
  }

  private var stateColor: Color {
    guard value != 0 else { return Color("AyurvedaNeutral") }
    let isSupportive = prefersPacifying ? value < 0 : value > 0
    return isSupportive
      ? Color("AyurvedaPacify")
      : Color("AyurvedaAggravate")
  }

  private var gradientColors: [Color] {
    prefersPacifying
      ? [
          Color("AyurvedaPacify"),
          Color("AyurvedaNeutral"),
          Color("AyurvedaAggravate"),
        ]
      : [
          Color("AyurvedaAggravate"),
          Color("AyurvedaNeutral"),
          Color("AyurvedaPacify"),
        ]
  }

  private var prefersPacifying: Bool {
    guard let profileWeight else { return true }
    return profileWeight >= (1.0 / 3.0)
  }

  private var profileWeight: Double? {
    guard let profileDistribution else { return nil }
    switch name.lowercased() {
    case "vata": return profileDistribution.vata
    case "pitta": return profileDistribution.pitta
    case "kapha": return profileDistribution.kapha
    default: return nil
    }
  }

  private func scaleValue(at x: CGFloat, width: CGFloat) -> Int {
    guard width > 0 else { return value }
    let progress = min(1, max(0, x / width))
    return Int((progress * 4).rounded()) - 2
  }

  private func reloadProfileDistribution() {
    profileDistribution = AyurvedaConstitutionStore
      .activeRecord()?
      .result
      .distribution
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

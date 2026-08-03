import SwiftUI
import UIKit

extension AyurvedaDosha {
  var identityColor: Color {
    switch self {
    case .vata: .blue
    case .pitta: .orange
    case .kapha: .green
    }
  }

  var identitySystemImage: String {
    switch self {
    case .vata: "wind"
    case .pitta: "flame"
    case .kapha: "drop.fill"
    }
  }
}

struct DoshaIdentityLabel: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let dosha: AyurvedaDosha
  var subtitle: String?
  var titleFont: Font = .body

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: dosha.identitySystemImage)
        .font(.title3.weight(.medium))
        .foregroundStyle(dosha.identityColor)
        .frame(width: 28)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(dosha.displayName)
          .font(titleFont)
          .foregroundStyle(effectManager.currentGlobalAccentColor)

        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(
              effectManager.currentGlobalAccentColor.opacity(0.72)
            )
        }
      }
    }
  }
}

struct DoshaScaleSelector: View {
  @ObservedObject private var effectManager = EffectManager.shared
  @Binding var value: Int
  @State private var profileDistribution: AyurvedaDoshaDistribution?

  let dosha: AyurvedaDosha
  let subtitle: String
  let isReadOnly: Bool

  private var name: String { dosha.displayName }

  private let values = [-2, -1, 0, 1, 2]

  init(
    value: Binding<Int>,
    dosha: AyurvedaDosha,
    subtitle: String
  ) {
    _value = value
    _profileDistribution = State(initialValue: nil)
    self.dosha = dosha
    self.subtitle = subtitle
    isReadOnly = false
  }

  init(readOnlyValue value: Int, dosha: AyurvedaDosha) {
    _value = .constant(min(2, max(-2, value)))
    _profileDistribution = State(initialValue: nil)
    self.dosha = dosha
    subtitle = ""
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 12) {
        identity
          .frame(width: 132, alignment: .leading)
        profileAwareScale(isInteractive: true)
          .frame(maxWidth: .infinity)
      }

      VStack(alignment: .leading, spacing: 6) {
        identity
        profileAwareScale(isInteractive: true)
      }
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
        DoshaIdentityLabel(
          dosha: dosha,
          titleFont: .caption.weight(.semibold)
        )
        .frame(width: 88, alignment: .leading)

        VStack(alignment: .leading, spacing: 6) {
          readOnlyEffect(presentation)
          readOnlyScale(presentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          DoshaIdentityLabel(
            dosha: dosha,
            titleFont: .caption.weight(.semibold)
          )
          Spacer(minLength: 8)
          readOnlyEffect(presentation)
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
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(stateColor)
  }

  private func readOnlyScale(
    _: AyurvedaDoshaEffectPresentation
  ) -> some View {
    profileAwareScale(isInteractive: false)
  }

  private var identity: some View {
    DoshaIdentityLabel(dosha: dosha, subtitle: subtitle)
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
    switch dosha {
    case .vata: return profileDistribution.vata
    case .pitta: return profileDistribution.pitta
    case .kapha: return profileDistribution.kapha
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

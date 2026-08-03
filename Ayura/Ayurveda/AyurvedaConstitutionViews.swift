import SwiftUI

enum AyurvedaConstitutionSetupMethod: String, Identifiable {
  case selfDeclared
  case questionnaire

  var id: String { rawValue }
}

private struct AyurvedaGlassSurfaceModifier: ViewModifier {
  @ObservedObject private var effectManager = EffectManager.shared

  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      .glassCardStyle(cornerRadius: cornerRadius)
  }
}

private struct AyurvedaGlassButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var effectManager = EffectManager.shared

  let fillsWidth: Bool
  let emphasized: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(
        emphasized
          ? .body.weight(.bold)
          : .subheadline.weight(.semibold)
      )
      .foregroundStyle(
        effectManager.currentGlobalAccentColor.opacity(isEnabled ? 1 : 0.38)
      )
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: fillsWidth ? .infinity : nil)
      .contentShape(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .glassCardStyle(cornerRadius: 16)
      .opacity(configuration.isPressed ? 0.78 : 1)
  }
}

private struct AyurvedaWizardNavigationButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var effectManager = EffectManager.shared

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .fontWeight(.bold)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .foregroundStyle(
        effectManager.currentGlobalAccentColor.opacity(isEnabled ? 1 : 0.38)
      )
      .contentShape(Rectangle())
      .glassCardStyle(cornerRadius: 20)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.78 : 1)
  }
}

private struct AyurvedaCustomHeader: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let title: String
  var leadingTitle: String?
  var trailingTitle: String?
  var leadingAction: (() -> Void)?
  var trailingAction: (() -> Void)?

  var body: some View {
    ZStack {
      Text(title)
        .font(.headline)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .lineLimit(1)
        .padding(.horizontal, 100)

      HStack {
        if let leadingTitle, let leadingAction {
          headerButton(leadingTitle, action: leadingAction)
        }

        Spacer(minLength: 12)

        if let trailingTitle, let trailingAction {
          headerButton(trailingTitle, action: trailingAction)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .padding(.horizontal)
    .padding(.top, 10)
    .padding(.bottom, 8)
  }

  private func headerButton(
    _ title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(title, action: action)
      .font(.body.weight(.semibold))
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .glassCardStyle(cornerRadius: 20)
      .foregroundStyle(effectManager.currentGlobalAccentColor)
  }
}

private extension View {
  func ayurvedaGlassSurface(cornerRadius: CGFloat = 20) -> some View {
    modifier(AyurvedaGlassSurfaceModifier(cornerRadius: cornerRadius))
  }

  func ayurvedaGlassButton(
    fillsWidth: Bool = false,
    emphasized: Bool = false
  ) -> some View {
    buttonStyle(
      AyurvedaGlassButtonStyle(
        fillsWidth: fillsWidth,
        emphasized: emphasized
      )
    )
  }

  func ayurvedaWizardNavigationButton() -> some View {
    buttonStyle(AyurvedaWizardNavigationButtonStyle())
  }
}

struct AyurvedaConstitutionOnboardingStepView: View {
  @Binding var draft: AyurvedaConstitutionDraft?
  let onBack: () -> Void
  let onContinue: () -> Void
  let onHeaderChange: (_ title: String, _ subtitle: String) -> Void

  var body: some View {
    AyurvedaConstitutionSetupView(
      method: draft?.source == .questionnaire
        ? .questionnaire
        : .selfDeclared,
      initialDraft: draft,
      isEmbedded: true,
      onCancel: onBack,
      onHeaderChange: { title, subtitle in
        onHeaderChange(title, subtitle)
      }
    ) { newDraft in
      draft = newDraft
      onContinue()
    }
  }
}

struct AyurvedaConstitutionSetupView: View {
  private enum Phase {
    case picker
    case questionnaire
    case result
  }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var effectManager = EffectManager.shared

  let method: AyurvedaConstitutionSetupMethod
  let isEmbedded: Bool
  let onCancel: () -> Void
  let onHeaderChange: (_ title: String, _ subtitle: String) -> Void
  let onComplete: (AyurvedaConstitutionDraft) -> Void

  @State private var phase: Phase
  @State private var selectedDeclaredTypeID: String?
  @State private var questionnaireAnswers = Array<AyurvedaDosha?>(
    repeating: nil,
    count: AyurvedaConstitutionQuestion.all.count
  )
  @State private var questionIndex = 0
  @State private var completedDraft: AyurvedaConstitutionDraft?

  init(
    method: AyurvedaConstitutionSetupMethod,
    initialDraft: AyurvedaConstitutionDraft? = nil,
    isEmbedded: Bool = false,
    onCancel: @escaping () -> Void = {},
    onHeaderChange: @escaping (_ title: String, _ subtitle: String) -> Void = { _, _ in },
    onComplete: @escaping (AyurvedaConstitutionDraft) -> Void
  ) {
    let resolvedMethod: AyurvedaConstitutionSetupMethod =
      initialDraft?.source == .questionnaire ? .questionnaire : method
    var savedAnswers = Array<AyurvedaDosha?>(
      repeating: nil,
      count: AyurvedaConstitutionQuestion.all.count
    )
    for (index, answer) in (initialDraft?.questionnaireAnswers ?? [])
      .prefix(savedAnswers.count)
      .enumerated()
    {
      savedAnswers[index] = answer
    }

    self.method = resolvedMethod
    self.isEmbedded = isEmbedded
    self.onCancel = onCancel
    self.onHeaderChange = onHeaderChange
    self.onComplete = onComplete
    _phase = State(
      initialValue: initialDraft == nil
        ? (resolvedMethod == .selfDeclared ? .picker : .questionnaire)
        : .result
    )
    _selectedDeclaredTypeID = State(
      initialValue: initialDraft?.declaredTypeID
    )
    _questionnaireAnswers = State(initialValue: savedAnswers)
    _questionIndex = State(
      initialValue: initialDraft?.source == .questionnaire
        ? max(0, AyurvedaConstitutionQuestion.all.count - 1)
        : 0
    )
    _completedDraft = State(initialValue: initialDraft)
  }

  @ViewBuilder
  var body: some View {
    Group {
      if isEmbedded {
        setupContent
      } else {
        ZStack {
          ThemeBackgroundView()
            .ignoresSafeArea()

          VStack(spacing: 0) {
            AyurvedaCustomHeader(
              title: navigationTitle,
              leadingTitle: "Cancel",
              leadingAction: cancelSetup
            )
            setupContent
          }
        }
      }
    }
    .tint(effectManager.currentGlobalAccentColor)
    .foregroundStyle(effectManager.currentGlobalAccentColor)
    .onAppear(perform: publishHeader)
    .onChange(of: phase) { _, _ in publishHeader() }
  }

  @ViewBuilder
  private var setupContent: some View {
    switch phase {
    case .picker:
      pickerView
    case .questionnaire:
      questionnaireView
    case .result:
      resultView
    }
  }

  private var navigationTitle: String {
    switch phase {
    case .picker: "Choose a profile"
    case .questionnaire: "Traditional profile"
    case .result: "Your result"
    }
  }

  private func publishHeader() {
    switch phase {
    case .picker:
      onHeaderChange(
        "Your traditional constitution",
        "Choose your constitution or answer 12 questions."
      )
    case .questionnaire:
      onHeaderChange(
        "Constitution questions",
        "Answer based on how you have usually been."
      )
    case .result:
      onHeaderChange(
        "Your constitution result",
        "Review your dosha distribution."
      )
    }
  }

  private var questionnaireProgress: Double {
    let questionCount = AyurvedaConstitutionQuestion.all.count
    guard questionCount > 1 else { return 1 }
    return Double(questionIndex) / Double(questionCount - 1)
  }

  private var pickerView: some View {
    VStack(spacing: 12) {
      List {
        ForEach(AyurvedaDeclaredTypeOption.all) { option in
          Button {
            selectedDeclaredTypeID = option.id
          } label: {
            ZStack {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(constitutionGradient(for: option.distribution))
                .opacity(selectedDeclaredTypeID == option.id ? 0.46 : 0.32)
                .allowsHitTesting(false)

              VStack(spacing: 2) {
                Text(option.displayName)
                  .foregroundStyle(effectManager.currentGlobalAccentColor)
                Text(option.detail)
                  .font(.caption)
                  .foregroundStyle(
                    effectManager.currentGlobalAccentColor.opacity(0.78)
                  )
              }
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 44)
              .padding(.vertical, 12)

              if selectedDeclaredTypeID == option.id {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(effectManager.currentGlobalAccentColor)
                  .frame(maxWidth: .infinity, alignment: .trailing)
                  .padding(.horizontal, 12)
              }
            }
            .frame(maxWidth: .infinity)
            .glassCardStyle(cornerRadius: 15)
            .overlay {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                  effectManager.currentGlobalAccentColor.opacity(
                    selectedDeclaredTypeID == option.id ? 0.85 : 0.16
                  ),
                  lineWidth: selectedDeclaredTypeID == option.id ? 2 : 1
                )
            }
            .contentShape(
              .interaction,
              RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)

      VStack(spacing: 10) {
        Button("Answer 12 questions instead") {
          phase = .questionnaire
        }
        .ayurvedaWizardNavigationButton()

        if isEmbedded {
          HStack(spacing: 16) {
            Button("Back", action: cancelSetup)
              .ayurvedaWizardNavigationButton()

            Button("Continue", action: completeDeclaredSelection)
              .ayurvedaWizardNavigationButton()
              .disabled(selectedDeclaredTypeID == nil)
          }
        } else {
          Button("Continue", action: completeDeclaredSelection)
            .ayurvedaWizardNavigationButton()
            .disabled(selectedDeclaredTypeID == nil)
        }
      }
    }
  }

  private func constitutionGradient(
    for distribution: AyurvedaDoshaDistribution
  ) -> LinearGradient {
    let components = distribution.ordered.filter { $0.value > 0.0001 }
    guard let first = components.first, let last = components.last else {
      return LinearGradient(
        colors: [.gray.opacity(0.35), .gray.opacity(0.2)],
        startPoint: .leading,
        endPoint: .trailing
      )
    }

    var stops: [Gradient.Stop] = [
      .init(color: doshaColor(first.dosha), location: 0)
    ]
    var boundary = 0.0

    if components.count > 1 {
      for index in 0..<(components.count - 1) {
        let current = components[index]
        let next = components[index + 1]
        boundary += current.value
        let halfTransition = min(
          0.04,
          min(current.value * 0.2, next.value * 0.2)
        )

        stops.append(
          .init(
            color: doshaColor(current.dosha),
            location: CGFloat(max(0, boundary - halfTransition))
          )
        )
        stops.append(
          .init(
            color: doshaColor(next.dosha),
            location: CGFloat(min(1, boundary + halfTransition))
          )
        )
      }
    }

    stops.append(.init(color: doshaColor(last.dosha), location: 1))
    return LinearGradient(
      stops: stops,
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private func doshaColor(_ dosha: AyurvedaDosha) -> Color {
    switch dosha {
    case .vata: .blue
    case .pitta: .orange
    case .kapha: .green
    }
  }

  private var questionnaireView: some View {
    let question = AyurvedaConstitutionQuestion.all[questionIndex]
    return VStack(spacing: 12) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            Text("Question \(questionIndex + 1) of 12")
              .font(.caption.weight(.semibold))
            Spacer()
            Text("\(Int((questionnaireProgress * 100).rounded()))%")
              .font(.caption)
          }
          ProgressView(value: questionnaireProgress)
            .tint(effectManager.currentGlobalAccentColor)

          Text(question.prompt)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

          VStack(spacing: 10) {
            ForEach(question.options) { option in
              questionnaireOption(
                option,
                isSelected: questionnaireAnswers[questionIndex] == option.dosha
              ) {
                questionnaireAnswers[questionIndex] = option.dosha
              }
            }
          }
        }
        .padding(.vertical)
      }

      HStack(spacing: 16) {
        Button("Back") {
          if questionIndex > 0 {
            questionIndex -= 1
          } else if method == .selfDeclared {
            phase = .picker
          } else {
            cancelSetup()
          }
        }
        .ayurvedaWizardNavigationButton()

        Button("Continue") {
          if questionIndex < AyurvedaConstitutionQuestion.all.count - 1 {
            questionIndex += 1
          } else {
            completeQuestionnaire()
          }
        }
        .ayurvedaWizardNavigationButton()
        .disabled(questionnaireAnswers[questionIndex] == nil)
      }
    }
  }

  private func questionnaireOption(
    _ option: AyurvedaQuestionOption,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(
            effectManager.currentGlobalAccentColor.opacity(
              isSelected ? 1 : 0.58
            )
          )
        Text(option.text)
          .foregroundStyle(effectManager.currentGlobalAccentColor)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassCardStyle(cornerRadius: 15)
      .overlay {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(
            effectManager.currentGlobalAccentColor.opacity(
              isSelected ? 0.85 : 0.16
            ),
            lineWidth: isSelected ? 2 : 1
          )
      }
      .contentShape(
        .interaction,
        RoundedRectangle(cornerRadius: 15, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }

  private var resultView: some View {
    VStack(spacing: 12) {
      ScrollView {
        VStack(spacing: 20) {
          if let completedDraft {
            AyurvedaConstitutionResultSummary(
              result: completedDraft.result,
              source: completedDraft.source,
              showsContextLabels: !isEmbedded
            )
          }
        }
        .padding(.vertical)
      }

      if let completedDraft {
        HStack(spacing: 16) {
          Button("Back") {
            phase = completedDraft.source == .selfDeclared
              ? .picker
              : .questionnaire
          }
          .ayurvedaWizardNavigationButton()

          Button("Continue") {
            onComplete(completedDraft)
            if !isEmbedded {
              dismiss()
            }
          }
          .ayurvedaWizardNavigationButton()
        }
      }
    }
  }

  private func completeQuestionnaire() {
    let answers = questionnaireAnswers.compactMap { $0 }
    guard answers.count == AyurvedaConstitutionQuestion.all.count else {
      return
    }
    completedDraft = AyurvedaConstitutionDraft(
      source: .questionnaire,
      prakriti: AyurvedaConstitutionResult.from(answers: answers).distribution,
      declaredTypeID: nil,
      questionnaireAnswers: answers
    )
    phase = .result
  }

  private func completeDeclaredSelection() {
    guard let option = AyurvedaDeclaredTypeOption.option(
      id: selectedDeclaredTypeID
    ) else {
      return
    }
    completedDraft = AyurvedaConstitutionDraft(
      source: .selfDeclared,
      prakriti: option.distribution,
      declaredTypeID: option.id,
      questionnaireAnswers: []
    )
    phase = .result
  }

  private func cancelSetup() {
    if isEmbedded {
      onCancel()
    } else {
      dismiss()
    }
  }
}

struct AyurvedaConstitutionResultSummary: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let result: AyurvedaConstitutionResult
  let source: AyurvedaConstitutionSource
  var showsContextLabels = true

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if showsContextLabels {
        Text("Your answers most closely match")
          .font(.subheadline)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
      }
      Text(result.label)
        .font(.title.weight(.bold))
        .foregroundStyle(effectManager.currentGlobalAccentColor)

      AyurvedaDistributionBars(distribution: result.distribution)

      if let uncertaintyNote = result.uncertaintyNote {
        Label(uncertaintyNote, systemImage: "equal.circle")
          .font(.subheadline)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
      }

      if showsContextLabels {
        Text(source.displayName)
          .font(.caption)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.68))
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .ayurvedaGlassSurface(cornerRadius: 20)
  }
}

private struct AyurvedaDistributionBars: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let distribution: AyurvedaDoshaDistribution

  var body: some View {
    VStack(spacing: 10) {
      bar(.vata, color: .blue)
      bar(.pitta, color: .orange)
      bar(.kapha, color: .green)
    }
  }

  private func bar(_ dosha: AyurvedaDosha, color: Color) -> some View {
    let percentage = distribution.percentage(for: dosha)
    return VStack(spacing: 4) {
      HStack {
        Text(dosha.displayName)
          .font(.caption.weight(.semibold))
        Spacer()
        Text("\(percentage)%")
          .font(.caption.monospacedDigit())
      }
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(color.opacity(0.15))
          Capsule()
            .fill(color)
            .frame(width: proxy.size.width * distribution[dosha])
        }
      }
      .frame(height: 7)
    }
  }
}

private struct AyurvedaInformationalDisclaimer: View {
  @ObservedObject private var effectManager = EffectManager.shared

  var body: some View {
    Label {
      Text(
        "This is a correspondence to a traditional wellness typology. It is informational only, is not medical advice, and does not diagnose or treat any condition."
      )
    } icon: {
      Image(systemName: "info.circle.fill")
    }
    .font(.footnote)
    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .ayurvedaGlassSurface(cornerRadius: 14)
  }
}

struct AyurvedaConstitutionEditorButton: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let title: String
  let profileID: UUID?
  @Binding var pendingDraft: AyurvedaConstitutionDraft?

  @State private var record: AyurvedaConstitutionRecord?
  @State private var isShowingManager = false

  init(
    title: String = "Ayurvedic profile",
    profileID: UUID?,
    pendingDraft: Binding<AyurvedaConstitutionDraft?>
  ) {
    self.title = title
    self.profileID = profileID
    _pendingDraft = pendingDraft
  }

  var body: some View {
    Button {
      isShowingManager = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "leaf.circle.fill")
          .font(.title3)
        Text(title)
          .font(.headline)
        Spacer()
        Text(resultLabel ?? "Set up")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
      }
      .foregroundStyle(effectManager.currentGlobalAccentColor)
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .glassCardStyle(cornerRadius: 20)
    }
    .buttonStyle(.plain)
    .onAppear(perform: reload)
    .onChange(of: profileID) { reload() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .ayurvedaConstitutionDidChange
      )
    ) { _ in
      reload()
    }
    .fullScreenCover(isPresented: $isShowingManager, onDismiss: reload) {
      if let profileID {
        AyurvedaConstitutionManagerView(profileID: profileID)
      } else {
        AyurvedaConstitutionDraftManagerView(draft: $pendingDraft)
      }
    }
  }

  private var resultLabel: String? {
    record?.result.label ?? pendingDraft?.result.label
  }

  private func reload() {
    record = profileID.flatMap { AyurvedaConstitutionStore.record(for: $0) }
  }
}

private struct AyurvedaConstitutionDraftManagerView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var effectManager = EffectManager.shared

  @Binding var draft: AyurvedaConstitutionDraft?
  @State private var setupMethod: AyurvedaConstitutionSetupMethod?

  var body: some View {
    ZStack {
      ThemeBackgroundView()
        .ignoresSafeArea()

      VStack(spacing: 0) {
        AyurvedaCustomHeader(
          title: "Ayurvedic profile",
          trailingTitle: "Done",
          trailingAction: { dismiss() }
        )

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 20) {
            if let draft {
              AyurvedaConstitutionResultSummary(
                result: draft.result,
                source: draft.source
              )

              Text("Change Ayurvedic profile")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

              setupButtons
            } else {
              Text(
                "Add an optional traditional profile to personalize Ayurvedic food ranking and explanations."
              )
              .foregroundStyle(
                effectManager.currentGlobalAccentColor.opacity(0.76)
              )

              setupButtons
            }
          }
          .padding()
          .padding(.bottom, 40)
        }
      }
    }
    .fullScreenCover(item: $setupMethod) { method in
      AyurvedaConstitutionSetupView(
        method: method,
        initialDraft: matchingDraft(for: method)
      ) { newDraft in
        draft = newDraft
        setupMethod = nil
      }
    }
    .tint(effectManager.currentGlobalAccentColor)
    .foregroundStyle(effectManager.currentGlobalAccentColor)
  }

  private var setupButtons: some View {
    VStack(spacing: 12) {
      Button("I already know my constitution") {
        setupMethod = .selfDeclared
      }
      .ayurvedaGlassButton(fillsWidth: true, emphasized: true)

      Button("Help me work it out") {
        setupMethod = .questionnaire
      }
      .ayurvedaGlassButton(fillsWidth: true)
    }
    .padding()
    .ayurvedaGlassSurface(cornerRadius: 18)
  }

  private func matchingDraft(
    for method: AyurvedaConstitutionSetupMethod
  ) -> AyurvedaConstitutionDraft? {
    guard let draft else { return nil }
    switch (method, draft.source) {
    case (.selfDeclared, .selfDeclared), (.questionnaire, .questionnaire):
      return draft
    default:
      return nil
    }
  }
}

struct AyurvedaHomeCheckInCard: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let profileID: UUID

  @State private var record: AyurvedaConstitutionRecord?
  @State private var isShowingCheckIn = false
  @State private var isDismissed = false

  var body: some View {
    Group {
      if shouldOfferCheckIn, !isDismissed {
        VStack(alignment: .leading, spacing: 8) {
          Label("Ayurvedic check-in", systemImage: "leaf.circle.fill")
            .font(.subheadline.weight(.semibold))
          Text(
            "Optionally update how sleep, digestion, appetite, energy and skin have felt over the past week or two."
          )
          .font(.caption)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
          HStack {
            Button("Not now") {
              isDismissed = true
            }
            .ayurvedaGlassButton()
            Spacer()
            Button("Check in") {
              isShowingCheckIn = true
            }
            .ayurvedaGlassButton(emphasized: true)
          }
        }
        .padding()
        .ayurvedaGlassSurface(cornerRadius: 18)
      }
    }
    .onAppear(perform: reload)
    .onReceive(
      NotificationCenter.default.publisher(
        for: .ayurvedaConstitutionDidChange
      )
    ) { _ in
      reload()
    }
    .fullScreenCover(isPresented: $isShowingCheckIn) {
      AyurvedaCheckInView(profileID: profileID) {
        reload()
        isShowingCheckIn = false
      }
    }
  }

  private var shouldOfferCheckIn: Bool {
    guard let record else { return false }
    guard let lastDate = record.latestCheckIn?.createdAt else {
      return Date().timeIntervalSince(record.updatedAt) >= 7 * 86_400
    }
    return Date().timeIntervalSince(lastDate) >= 7 * 86_400
  }

  private func reload() {
    record = AyurvedaConstitutionStore.record(for: profileID)
  }
}

struct AyurvedaConstitutionManagerView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var effectManager = EffectManager.shared

  let profileID: UUID

  @State private var record: AyurvedaConstitutionRecord?
  @State private var setupMethod: AyurvedaConstitutionSetupMethod?
  @State private var isShowingCheckIn = false
  @State private var isShowingDeleteConfirmation = false

  var body: some View {
    ZStack {
      ThemeBackgroundView()
        .ignoresSafeArea()

      VStack(spacing: 0) {
        AyurvedaCustomHeader(
          title: "Ayurvedic profile",
          trailingTitle: "Done",
          trailingAction: { dismiss() }
        )

        List {
          if let record {
            Section {
              AyurvedaConstitutionResultSummary(
                result: record.result,
                source: record.source
              )
              .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
              VStack(alignment: .leading, spacing: 12) {
                if let checkIn = record.latestCheckIn {
                  AyurvedaDistributionBars(
                    distribution: checkIn.distribution
                  )
                  Text(
                    checkIn.createdAt.formatted(
                      date: .abbreviated,
                      time: .shortened
                    )
                  )
                  .font(.caption)
                  .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
                  Text(checkInStatus(record))
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
                } else {
                  Text(
                    "No recent check-in. Food ranking currently uses the long-term profile only."
                  )
                  .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
                }
                Button("Check in for the past week or two") {
                  isShowingCheckIn = true
                }
                .ayurvedaGlassButton(fillsWidth: true, emphasized: true)
              }
              .padding()
              .ayurvedaGlassSurface(cornerRadius: 18)
            } header: {
              Text("Current pattern")
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !record.questionnaireAnswers.isEmpty {
              Section {
                DisclosureGroup("Review my answers") {
                  ForEach(
                    Array(
                      AyurvedaConstitutionQuestion.all.enumerated()
                    ),
                    id: \.offset
                  ) { index, question in
                    VStack(alignment: .leading, spacing: 3) {
                      Text(question.prompt)
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                      if record.questionnaireAnswers.indices.contains(index),
                        let option = question.option(
                          for: record.questionnaireAnswers[index]
                        )
                      {
                        Text(option.text)
                          .font(.subheadline.weight(.medium))
                          .foregroundStyle(effectManager.currentGlobalAccentColor)
                      }
                    }
                    .padding(.vertical, 3)
                  }
                }
                .padding()
                .ayurvedaGlassSurface(cornerRadius: 18)
              }
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
            }

            Section {
              VStack(spacing: 12) {
                Button("Choose a known constitution") {
                  setupMethod = .selfDeclared
                }
                .ayurvedaGlassButton(fillsWidth: true)
                Button("Answer the 12 questions again") {
                  setupMethod = .questionnaire
                }
                .ayurvedaGlassButton(fillsWidth: true)
              }
              .padding()
              .ayurvedaGlassSurface(cornerRadius: 18)
            } header: {
              Text("Change profile")
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
              VStack(alignment: .leading, spacing: 12) {
                Text(
                  "This profile and its answers are stored on this device and in the private metadata event of your Ayura profile calendar. A calendar account may sync them between your devices. Ayura does not send them to advertising or analytics providers."
                )
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
                Button(
                  "Delete complete Ayurvedic profile",
                  role: .destructive
                ) {
                  isShowingDeleteConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .glassCardStyle(cornerRadius: 16)
              }
              .padding()
              .ayurvedaGlassSurface(cornerRadius: 18)
            } header: {
              Text("Privacy controls")
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          } else {
            Section {
              VStack(alignment: .leading, spacing: 12) {
                Text(
                  "Add an optional traditional profile to personalize Ayurvedic food ranking and explanations."
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
                Button("I already know my constitution") {
                  setupMethod = .selfDeclared
                }
                .ayurvedaGlassButton(fillsWidth: true, emphasized: true)
                Button("Help me work it out") {
                  setupMethod = .questionnaire
                }
                .ayurvedaGlassButton(fillsWidth: true)
              }
              .padding()
              .ayurvedaGlassSurface(cornerRadius: 18)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
      }
    }
    .onAppear(perform: reload)
    .fullScreenCover(item: $setupMethod) { method in
      AyurvedaConstitutionSetupView(method: method) { draft in
        AyurvedaConstitutionStore.save(draft, for: profileID)
        reload()
        setupMethod = nil
      }
    }
    .fullScreenCover(isPresented: $isShowingCheckIn) {
      AyurvedaCheckInView(profileID: profileID) {
        reload()
        isShowingCheckIn = false
      }
    }
    .confirmationDialog(
      "Delete the complete Ayurvedic profile?",
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete profile and check-in", role: .destructive) {
        AyurvedaConstitutionStore.delete(profileID: profileID)
        reload()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This removes the answers, derived traditional profile and current check-in from this device and, when calendar access is available, from the Ayura profile calendar metadata."
      )
    }
    .tint(effectManager.currentGlobalAccentColor)
    .foregroundStyle(effectManager.currentGlobalAccentColor)
  }

  private func checkInStatus(_ record: AyurvedaConstitutionRecord) -> String {
    let percent = Int((record.vikritiWeight() / 0.7 * 100).rounded())
    if percent <= 0 {
      return "This check-in is no longer influencing food ranking."
    }
    return "Current check-in influence: \(percent)% of its full weight."
  }

  private func reload() {
    record = AyurvedaConstitutionStore.record(for: profileID)
  }
}

private struct AyurvedaCheckInView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var effectManager = EffectManager.shared

  let profileID: UUID
  let onComplete: () -> Void

  @State private var answers = Array<AyurvedaDosha?>(
    repeating: nil,
    count: AyurvedaCheckInQuestion.all.count
  )
  @State private var questionIndex = 0
  @State private var isReviewing = false

  var body: some View {
    ZStack {
      ThemeBackgroundView()
        .ignoresSafeArea()

      VStack(spacing: 0) {
        AyurvedaCustomHeader(
          title: "Current check-in",
          leadingTitle: "Cancel",
          leadingAction: { dismiss() }
        )

        Group {
          if isReviewing {
            review
          } else {
            question
          }
        }
      }
    }
    .tint(effectManager.currentGlobalAccentColor)
    .foregroundStyle(effectManager.currentGlobalAccentColor)
  }

  private var question: some View {
    let item = AyurvedaCheckInQuestion.all[questionIndex]
    return ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("Over the past week or two")
          .font(.subheadline)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
        ProgressView(
          value: Double(questionIndex + 1),
          total: Double(AyurvedaCheckInQuestion.all.count)
        )
        .tint(effectManager.currentGlobalAccentColor)
        Text(item.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
        Text(item.prompt)
          .font(.title2.weight(.semibold))

        ForEach(item.options) { option in
          Button {
            answers[questionIndex] = option.dosha
          } label: {
            HStack {
              Image(
                systemName: answers[questionIndex] == option.dosha
                  ? "checkmark.circle.fill"
                  : "circle"
              )
              .foregroundStyle(
                effectManager.currentGlobalAccentColor.opacity(
                  answers[questionIndex] == option.dosha ? 1 : 0.58
                )
              )
              Text(option.text)
                .multilineTextAlignment(.leading)
              Spacer()
            }
            .padding()
            .glassCardStyle(cornerRadius: 15)
            .overlay {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                  effectManager.currentGlobalAccentColor.opacity(
                    answers[questionIndex] == option.dosha ? 0.85 : 0.16
                  ),
                  lineWidth: answers[questionIndex] == option.dosha ? 2 : 1
                )
            }
            .contentShape(
              .interaction,
              RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
          }
          .buttonStyle(.plain)
        }

        HStack {
          if questionIndex > 0 {
            Button("Back") { questionIndex -= 1 }
              .ayurvedaGlassButton()
          }
          Spacer()
          Button(
            questionIndex == AyurvedaCheckInQuestion.all.count - 1
              ? "Review"
              : "Next"
          ) {
            if questionIndex == AyurvedaCheckInQuestion.all.count - 1 {
              isReviewing = true
            } else {
              questionIndex += 1
            }
          }
          .ayurvedaGlassButton(emphasized: true)
          .disabled(answers[questionIndex] == nil)
        }
      }
      .padding()
    }
  }

  private var review: some View {
    let completed = answers.compactMap { $0 }
    let distribution = AyurvedaConstitutionResult
      .from(answers: completed)
      .distribution
    return ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("Your current pattern")
          .font(.title2.weight(.semibold))
        AyurvedaDistributionBars(distribution: distribution)
          .padding()
          .ayurvedaGlassSurface(cornerRadius: 18)
        Text(
          "A fresh check-in influences food ranking more than the long-term profile. Its influence starts to fade after seven days and reaches zero after 30 days."
        )
        .font(.subheadline)
        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.76))
        AyurvedaInformationalDisclaimer()

        Button("Save check-in") {
          AyurvedaConstitutionStore.save(
            checkInAnswers: completed,
            for: profileID
          )
          onComplete()
          dismiss()
        }
        .ayurvedaGlassButton(fillsWidth: true, emphasized: true)
        .disabled(completed.count != AyurvedaCheckInQuestion.all.count)

        Button("Go back") {
          isReviewing = false
        }
        .ayurvedaGlassButton()
      }
      .padding()
    }
  }
}

struct AyurvedaPersonalizedFoodFitView: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let display: AyurvedaDisplay

  @State private var target: AyurvedaDoshaDistribution?
  @State private var activeProfileID: UUID?
  @State private var isShowingManager = false

  var body: some View {
    Group {
      if let target {
        let fit = AyurvedaFoodFitPresentation.make(
          target: target,
          vata: display.vata,
          pitta: display.pitta,
          kapha: display.kapha,
          rasa: display.rasa,
          virya: display.virya,
          gunas: display.gunas
        )
        VStack(alignment: .leading, spacing: 8) {
          personalizedCard(fit)
        }
      } else if activeProfileID != nil {
        VStack(alignment: .leading, spacing: 8) {
          Text("Personal Ayurvedic fit is not set")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(effectManager.currentGlobalAccentColor)
          Text(
            "Add an optional traditional profile to personalize this explanation."
          )
          .font(.caption)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
          Button("Set up profile") {
            isShowingManager = true
          }
          .ayurvedaGlassButton()
        }
      }
    }
    .onAppear(perform: reload)
    .onReceive(
      NotificationCenter.default.publisher(
        for: .ayurvedaConstitutionDidChange
      )
    ) { _ in
      reload()
    }
    .fullScreenCover(isPresented: $isShowingManager) {
      if let activeProfileID {
        AyurvedaConstitutionManagerView(profileID: activeProfileID)
      }
    }
  }

  private func personalizedCard(
    _ fit: AyurvedaFoodFitPresentation
  ) -> some View {
    let color: Color = switch fit.direction {
    case .supportive: Color("AyurvedaPacify")
    case .mixed: Color("AyurvedaNeutral")
    case .lessSupportive: Color("AyurvedaAggravate")
    }
    return VStack(alignment: .leading, spacing: 5) {
      Label(fit.title, systemImage: "person.crop.circle.badge.checkmark")
        .font(.subheadline.weight(.semibold))
      Text(fit.explanation)
        .font(.caption)
      Text("Personal fit changes ranking only; it never hides this food.")
        .font(.caption2)
        .foregroundStyle(color.opacity(0.76))
    }
    .foregroundStyle(color)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassCardStyle(cornerRadius: 14)
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(color.opacity(0.5), lineWidth: 1)
    }
  }

  private func reload() {
    activeProfileID = AyurvedaConstitutionStore.activeProfileID
    target = AyurvedaConstitutionStore.activeTarget()
  }
}

struct AyurvedaPersonalFitBadge: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let metadata: AyurvedaCanonicalSearchMetadata?

  @State private var target: AyurvedaDoshaDistribution?

  var body: some View {
    Group {
      if let metadata, let target {
        let fit = AyurvedaFoodFitPresentation.make(
          target: target,
          vata: metadata.doshaVata,
          pitta: metadata.doshaPitta,
          kapha: metadata.doshaKapha,
          rasa: metadata.rasa,
          virya: metadata.virya,
          gunas: metadata.gunas
        )
        Label(fit.title, systemImage: icon(for: fit.direction))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(color(for: fit.direction))
      } else if metadata == nil {
        Label("No Ayurvedic profile", systemImage: "questionmark.circle")
          .font(.caption2)
          .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
      }
    }
    .onAppear {
      target = AyurvedaConstitutionStore.activeTarget()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .ayurvedaConstitutionDidChange
      )
    ) { _ in
      target = AyurvedaConstitutionStore.activeTarget()
    }
  }

  private func icon(
    for direction: AyurvedaFoodFitPresentation.Direction
  ) -> String {
    switch direction {
    case .supportive: "leaf.fill"
    case .mixed: "equal.circle.fill"
    case .lessSupportive: "arrow.down.right.circle.fill"
    }
  }

  private func color(
    for direction: AyurvedaFoodFitPresentation.Direction
  ) -> Color {
    switch direction {
    case .supportive: Color("AyurvedaPacify")
    case .mixed: Color("AyurvedaNeutral")
    case .lessSupportive: Color("AyurvedaAggravate")
    }
  }
}

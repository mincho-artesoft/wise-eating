import SwiftData
import SwiftUI

struct AyurvedaForm: Sendable {
  var vata: Int
  var pitta: Int
  var kapha: Int
  var rasa: Set<String>
  var virya: String?
  var vipaka: String?
  var gunas: Set<String>

  init(
    vata: Int = 0,
    pitta: Int = 0,
    kapha: Int = 0,
    rasa: Set<String> = [],
    virya: String? = nil,
    vipaka: String? = nil,
    gunas: Set<String> = []
  ) {
    self.vata = vata
    self.pitta = pitta
    self.kapha = kapha
    self.rasa = rasa
    self.virya = virya
    self.vipaka = vipaka
    self.gunas = gunas
  }

  static var neutral: AyurvedaForm {
    AyurvedaForm()
  }

  static func prefilled(
    from computed: AyurvedaDisplayMath.Computed?
  ) -> AyurvedaForm {
    guard let computed else {
      return .neutral
    }
    return AyurvedaForm(
      vata: computed.vata,
      pitta: computed.pitta,
      kapha: computed.kapha,
      virya: computed.virya
    )
  }

  var isEmpty: Bool {
    vata == 0
      && pitta == 0
      && kapha == 0
      && rasa.isEmpty
      && virya == nil
      && vipaka == nil
      && gunas.isEmpty
  }
}

struct AyurvedaEditorSection: View {
  @Environment(\.colorScheme) private var colorScheme

  private enum ViryaPickerOption: String, CaseIterable, Identifiable {
    case cooling = "Cooling"
    case neutral = "Neutral"
    case heating = "Heating"

    var id: Self { self }
    var storedValue: String { rawValue.lowercased() }

    var tint: Color {
      switch self {
      case .cooling: return .blue
      case .neutral: return .secondary
      case .heating: return .orange
      }
    }

    var systemImage: String {
      switch self {
      case .cooling: return "snowflake"
      case .neutral: return "minus"
      case .heating: return "flame"
      }
    }
  }

  private enum VipakaPickerOption: String, CaseIterable, Identifiable {
    case sweet = "Sweet"
    case sour = "Sour"
    case pungent = "Pungent"

    var id: Self { self }
    var storedValue: String { rawValue.lowercased() }
  }

  private static let rasaValues = [
    "sweet", "sour", "salty", "pungent", "bitter", "astringent"
  ]
  private static let gunaValues = [
    "dense", "dry", "heavy", "light", "liquid",
    "oily", "penetrating", "rough", "sharp", "slimy", "smooth", "soft"
  ]
  @ObservedObject private var effectManager = EffectManager.shared
  @Binding var form: AyurvedaForm

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      doshaGroup
      sectionDivider
      rasaGroup
      sectionDivider
      viryaGroup
      sectionDivider
      vipakaGroup
      sectionDivider
      gunaGroup
    }
  }

  private var sectionDivider: some View {
    Divider()
      .padding(.vertical, 12)
  }

  private var header: some View {
    Text("Dosha Effects")
      .font(.caption.bold())
      .foregroundStyle(effectManager.currentGlobalAccentColor)
  }

  private var doshaGroup: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      DoshaScaleSelector(
        value: $form.vata,
        name: "Vata",
        subtitle: "Movement & Air",
        systemImage: "wind",
        tint: .blue
      )
      Divider()
      DoshaScaleSelector(
        value: $form.pitta,
        name: "Pitta",
        subtitle: "Fire & Transformation",
        systemImage: "flame",
        tint: .orange
      )
      Divider()
      DoshaScaleSelector(
        value: $form.kapha,
        name: "Kapha",
        subtitle: "Structure & Water",
        systemImage: "leaf",
        tint: .green
      )
    }
  }

  private var rasaGroup: some View {
    editorGroup(title: "Rasa (taste)") {
      ChipGrid {
        ForEach(Self.rasaValues, id: \.self) { value in
          GlassChipView(
            label: value.capitalized,
            color: rasaTint(value),
            systemImage: rasaIcon(value),
            textColor: effectManager.currentGlobalAccentColor,
            isSelected: form.rasa.contains(value),
            action: { toggleRasa(value) }
          )
        }
      }
    }
  }

  private var viryaGroup: some View {
    editorGroup(title: "Virya (energy)") {
      WrappingSegmentedControl(
        selection: viryaSelection,
        layoutMode: .wrap,
        selectionTint: \.tint,
        systemImage: \.systemImage
      )
        .frame(minHeight: 36)
        .padding(2)
        .background(.thinMaterial, in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12))
        }
        .accessibilityLabel("Virya energy")
    }
  }

  private var vipakaGroup: some View {
    editorGroup(title: "Vipaka (post-digestive)") {
      WrappingSegmentedControl(
        selection: vipakaSelection,
        layoutMode: .wrap,
        selectionTint: { _ in effectManager.currentGlobalAccentColor }
      )
        .frame(minHeight: 36)
        .padding(2)
        .background(.thinMaterial, in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12))
        }
        .accessibilityLabel("Vipaka post-digestive effect")
    }
  }

  private var gunaGroup: some View {
    editorGroup(title: "Gunas (qualities)") {
      ChipGrid {
        ForEach(Self.gunaValues, id: \.self) { value in
          GlassChipView(
            label: value.capitalized,
            color: effectManager.currentGlobalAccentColor,
            systemImage: nil,
            textColor: effectManager.currentGlobalAccentColor,
            isSelected: form.gunas.contains(value),
            action: { toggleGuna(value) }
          )
        }
      }
    }
  }

  private func editorGroup<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(effectManager.currentGlobalAccentColor)
      content()
    }
  }

  private func toggleRasa(_ value: String) {
    if form.rasa.contains(value) {
      form.rasa.remove(value)
    } else {
      form.rasa.insert(value)
    }
  }

  private func toggleGuna(_ value: String) {
    if form.gunas.contains(value) {
      form.gunas.remove(value)
    } else {
      form.gunas.insert(value)
    }
  }

  private var viryaSelection: Binding<ViryaPickerOption?> {
    Binding(
      get: {
        guard let storedValue = form.virya else { return nil }
        return ViryaPickerOption.allCases.first { $0.storedValue == storedValue }
      },
      set: { form.virya = $0?.storedValue }
    )
  }

  private var vipakaSelection: Binding<VipakaPickerOption?> {
    Binding(
      get: {
        guard let storedValue = form.vipaka else { return nil }
        return VipakaPickerOption.allCases.first { $0.storedValue == storedValue }
      },
      set: { form.vipaka = $0?.storedValue }
    )
  }

  private func rasaIcon(_ value: String) -> String {
    switch value {
    case "sweet": return "sparkles"
    case "sour": return "drop.fill"
    case "salty": return "water.waves"
    case "pungent": return "flame.fill"
    case "bitter": return "leaf.fill"
    default: return "circle.grid.3x3.fill"
    }
  }

  private func rasaTint(_ value: String) -> Color {
    switch value {
    case "sweet": return .purple
    case "sour": return .yellow
    case "salty": return .teal
    case "pungent": return .red
    case "bitter": return .green
    default: return .indigo
    }
  }
}

struct AyurvedaRecipeEditorSection: View {
  @Binding var isManualOverride: Bool
  @Binding var form: AyurvedaForm

  let computation: AyurvedaIngredientComputation

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle("Set manually", isOn: $isManualOverride)
        .onChange(of: isManualOverride) { wasManual, isManual in
          if isManual && !wasManual {
            form = .prefilled(from: computation.computed)
          }
        }
      if isManualOverride {
        AyurvedaEditorSection(form: $form)
      } else {
        AyurvedaAutomaticPreview(computation: computation)
      }
    }
  }
}

private struct AyurvedaAutomaticPreview: View {
  let computation: AyurvedaIngredientComputation

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if computation.hasIngredients {
        if let computed = computation.computed {
          DoshaBarsView(
            vata: computed.vata,
            pitta: computed.pitta,
            kapha: computed.kapha
          )
        } else {
          Text("Not enough recognizable ingredients yet.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

@MainActor
enum AyurvedaUserProfileStore {
  static func form(foodId: Int, context: ModelContext) -> AyurvedaForm? {
    guard let profile = profile(foodId: foodId, context: context) else {
      return nil
    }
    return AyurvedaForm(
      vata: profile.doshaVata,
      pitta: profile.doshaPitta,
      kapha: profile.doshaKapha,
      rasa: Set(profile.rasa),
      virya: profile.virya,
      vipaka: profile.vipaka,
      gunas: Set(profile.gunas)
    )
  }

  static func resolvedFormForDuplication(
    foodId: Int,
    context: ModelContext
  ) -> AyurvedaForm? {
    let sourceFoodId = foodId
    var descriptor = FetchDescriptor<FoodItem>(
      predicate: #Predicate<FoodItem> { food in
        food.id == sourceFoodId
      }
    )
    descriptor.fetchLimit = 1

    guard
      let food = try? context.fetch(descriptor).first,
      let resolution = try? AyurvedaResolver.resolve(for: food, context: context),
      let display = AyurvedaDisplay.make(from: resolution)
    else {
      return nil
    }

    return AyurvedaForm(
      vata: display.vata,
      pitta: display.pitta,
      kapha: display.kapha,
      rasa: Set(display.rasa),
      virya: display.virya,
      vipaka: display.vipaka,
      gunas: Set(display.gunas)
    )
  }

  static func upsert(
    form: AyurvedaForm,
    for food: FoodItem,
    context: ModelContext
  ) {
    let existing = profile(foodId: food.id, context: context)
    guard existing != nil || !form.isEmpty else {
      return
    }

    let profile = existing ?? makeProfile(form: form, food: food)
    apply(form: form, food: food, to: profile)
    if existing == nil {
      context.insert(profile)
    }
  }

  static func remove(foodId: Int, context: ModelContext) {
    guard let existing = profile(foodId: foodId, context: context) else {
      return
    }
    context.delete(existing)
  }

  private static func profile(
    foodId: Int,
    context: ModelContext
  ) -> AyurvedaProfile? {
    let id = profileID(foodId)
    var descriptor = FetchDescriptor<AyurvedaProfile>(
      predicate: #Predicate<AyurvedaProfile> { profile in
        profile.id == id
      }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  private static func makeProfile(
    form: AyurvedaForm,
    food: FoodItem
  ) -> AyurvedaProfile {
    AyurvedaProfile(
      id: profileID(food.id),
      kind: "user",
      foodId: food.id,
      name: food.name,
      category: food.category?.first?.rawValue ?? "",
      doshaVata: form.vata,
      doshaPitta: form.pitta,
      doshaKapha: form.kapha,
      seasons: [],
      timeOfDay: [],
      viruddha: [],
      provenance: ["user-editor"],
      confidenceAyur: 1.0,
      confidenceSci: nil,
      qualityState: "user",
      reviewNote: nil,
      seedVersion: bundleSeedVersion,
      sanskrit: nil,
      rasa: form.rasa.sorted(),
      virya: form.virya,
      vipaka: form.vipaka,
      gunas: form.gunas.sorted(),
      prabhava: nil,
      agniEffect: nil,
      digestibility: nil,
      preparation: nil,
      servingsJSON: nil,
      meal: nil,
      servingsCount: nil,
      prepMinutes: nil,
      cookMinutes: nil,
      guidance: nil
    )
  }

  private static func apply(
    form: AyurvedaForm,
    food: FoodItem,
    to profile: AyurvedaProfile
  ) {
    profile.kind = "user"
    profile.foodId = food.id
    profile.foodIsPlaceholder = false
    profile.name = food.name
    profile.category = food.category?.first?.rawValue ?? ""
    profile.doshaVata = form.vata
    profile.doshaPitta = form.pitta
    profile.doshaKapha = form.kapha
    profile.seasons = []
    profile.timeOfDay = []
    profile.viruddha = []
    profile.provenance = ["user-editor"]
    profile.confidenceAyur = 1.0
    profile.confidenceSci = nil
    profile.qualityState = "user"
    profile.reviewNote = nil
    profile.engineExcluded = false
    profile.seedVersion = bundleSeedVersion
    profile.sanskrit = nil
    profile.aliases = []
    profile.rasa = form.rasa.sorted()
    profile.virya = form.virya
    profile.vipaka = form.vipaka
    profile.gunas = form.gunas.sorted()
    profile.prabhava = nil
    profile.agniEffect = nil
    profile.digestibility = nil
    profile.combinations = []
    profile.contraindications = []
    profile.preparation = nil
    profile.servingsJSON = nil
    profile.meal = nil
    profile.servingsCount = nil
    profile.prepMinutes = nil
    profile.cookMinutes = nil
    profile.steps = []
    profile.guidance = nil
  }

  private static func profileID(_ foodId: Int) -> String {
    "user.\(foodId)"
  }

  private static var bundleSeedVersion: Int {
    (try? AyurvedaSeeder.bundleSeedVersion()) ?? 0
  }
}

import SwiftData
import SwiftUI

struct AyurvedaForm: Sendable {
  var vata = 0
  var pitta = 0
  var kapha = 0
  var rasa: Set<String> = []
  var virya: String?
  var vipaka: String?
  var gunas: Set<String> = []

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
  private static let rasaValues = [
    "sweet", "sour", "salty", "pungent", "bitter", "astringent"
  ]
  private static let viryaValues = ["heating", "cooling", "neutral"]
  private static let vipakaValues = ["sweet", "sour", "pungent"]
  private static let gunaValues = [
    "dense", "dry", "heavy", "light", "liquid",
    "oily", "rough", "sharp", "smooth", "soft"
  ]

  @ObservedObject private var effectManager = EffectManager.shared
  @Binding var form: AyurvedaForm

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      doshaSteppers
      toggleGroup(title: "Rasa (taste)", values: Self.rasaValues, selection: $form.rasa)
      optionalPicker(title: "Virya (energy)", values: Self.viryaValues, selection: $form.virya)
      optionalPicker(title: "Vipaka (post-digestive)", values: Self.vipakaValues, selection: $form.vipaka)
      toggleGroup(title: "Gunas (qualities)", values: Self.gunaValues, selection: $form.gunas)
      Text("Saved as tier 'User' — shown in the food's Ayurveda section.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var doshaSteppers: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Dosha effects")
        .font(.caption)
        .foregroundStyle(.secondary)
      doshaStepper(title: "Vata", value: $form.vata)
      doshaStepper(title: "Pitta", value: $form.pitta)
      doshaStepper(title: "Kapha", value: $form.kapha)
    }
  }

  private func doshaStepper(title: String, value: Binding<Int>) -> some View {
    Stepper(value: value, in: -2...2) {
      HStack {
        Text(title)
        Spacer()
        Text(
          AyurvedaDisplayMath.valueString(value.wrappedValue)
            + " "
            + AyurvedaDisplayMath.effectLabel(value.wrappedValue)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func toggleGroup(
    title: String,
    values: [String],
    selection: Binding<Set<String>>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      CustomFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(values, id: \.self) { value in
          Button {
            toggle(value, in: selection)
          } label: {
            Text(value)
              .font(.caption)
              .padding(.horizontal, 9)
              .padding(.vertical, 5)
              .foregroundStyle(effectManager.currentGlobalAccentColor)
              .background(
                effectManager.currentGlobalAccentColor.opacity(
                  selection.wrappedValue.contains(value) ? 0.35 : 0.12
                ),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func optionalPicker(
    title: String,
    values: [String],
    selection: Binding<String?>
  ) -> some View {
    HStack {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Picker(title, selection: selection) {
        Text("—").tag(String?.none)
        ForEach(values, id: \.self) { value in
          Text(value).tag(String?.some(value))
        }
      }
      .pickerStyle(.menu)
    }
  }

  private func toggle(_ value: String, in selection: Binding<Set<String>>) {
    if selection.wrappedValue.contains(value) {
      selection.wrappedValue.remove(value)
    } else {
      selection.wrappedValue.insert(value)
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

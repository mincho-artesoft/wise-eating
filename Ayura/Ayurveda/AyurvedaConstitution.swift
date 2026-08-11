import Foundation

enum AyurvedaDosha: String, Codable, CaseIterable, Identifiable, Sendable {
  case vata
  case pitta
  case kapha

  var id: String { rawValue }
  var displayName: String { rawValue.capitalized }
}

struct AyurvedaDoshaDistribution: Codable, Equatable, Sendable {
  let vata: Double
  let pitta: Double
  let kapha: Double

  static let balanced = AyurvedaDoshaDistribution(
    vata: 1,
    pitta: 1,
    kapha: 1
  )

  init(vata: Double, pitta: Double, kapha: Double) {
    let values = [
      max(0, vata.isFinite ? vata : 0),
      max(0, pitta.isFinite ? pitta : 0),
      max(0, kapha.isFinite ? kapha : 0),
    ]
    let total = values.reduce(0, +)
    if total > 0 {
      self.vata = values[0] / total
      self.pitta = values[1] / total
      self.kapha = values[2] / total
    } else {
      self.vata = 1.0 / 3.0
      self.pitta = 1.0 / 3.0
      self.kapha = 1.0 / 3.0
    }
  }

  subscript(_ dosha: AyurvedaDosha) -> Double {
    switch dosha {
    case .vata: vata
    case .pitta: pitta
    case .kapha: kapha
    }
  }

  var ordered: [(dosha: AyurvedaDosha, value: Double)] {
    AyurvedaDosha.allCases
      .map { ($0, self[$0]) }
      .sorted {
        if $0.1 == $1.1 {
          let lhsIndex = AyurvedaDosha.allCases.firstIndex(of: $0.0) ?? 0
          let rhsIndex = AyurvedaDosha.allCases.firstIndex(of: $1.0) ?? 0
          return lhsIndex < rhsIndex
        }
        return $0.1 > $1.1
      }
  }

  func percentage(for dosha: AyurvedaDosha) -> Int {
    Int((self[dosha] * 100).rounded())
  }

  func doshaFit(vata: Int, pitta: Int, kapha: Int) -> Double {
    self.vata * Double(-vata)
      + self.pitta * Double(-pitta)
      + self.kapha * Double(-kapha)
  }
}

enum AyurvedaConstitutionSource: String, Codable, Sendable {
  case selfDeclared
  case questionnaire

  var displayName: String? {
    switch self {
    case .selfDeclared: nil
    case .questionnaire: "From the 12-question profile"
    }
  }
}

struct AyurvedaDeclaredTypeOption: Identifiable, Equatable, Sendable {
  enum Group: String, CaseIterable, Sendable {
    case single = "Single"
    case dual = "Dual"
    case balanced = "Balanced"
  }

  let id: String
  let displayName: String
  let detail: String
  let group: Group
  let distribution: AyurvedaDoshaDistribution

  static let all: [AyurvedaDeclaredTypeOption] = [
    .init(
      id: "vata",
      displayName: "Vata",
      detail: "Vata leads",
      group: .single,
      distribution: .init(vata: 1, pitta: 0, kapha: 0)
    ),
    .init(
      id: "pitta",
      displayName: "Pitta",
      detail: "Pitta leads",
      group: .single,
      distribution: .init(vata: 0, pitta: 1, kapha: 0)
    ),
    .init(
      id: "kapha",
      displayName: "Kapha",
      detail: "Kapha leads",
      group: .single,
      distribution: .init(vata: 0, pitta: 0, kapha: 1)
    ),
    .init(
      id: "vata-pitta-even",
      displayName: "Vata–Pitta",
      detail: "Even pair",
      group: .dual,
      distribution: .init(vata: 1, pitta: 1, kapha: 0)
    ),
    .init(
      id: "vata-pitta",
      displayName: "Vata–Pitta",
      detail: "Vata leads",
      group: .dual,
      distribution: .init(vata: 0.6, pitta: 0.4, kapha: 0)
    ),
    .init(
      id: "pitta-vata",
      displayName: "Pitta–Vata",
      detail: "Pitta leads",
      group: .dual,
      distribution: .init(vata: 0.4, pitta: 0.6, kapha: 0)
    ),
    .init(
      id: "pitta-kapha-even",
      displayName: "Pitta–Kapha",
      detail: "Even pair",
      group: .dual,
      distribution: .init(vata: 0, pitta: 1, kapha: 1)
    ),
    .init(
      id: "pitta-kapha",
      displayName: "Pitta–Kapha",
      detail: "Pitta leads",
      group: .dual,
      distribution: .init(vata: 0, pitta: 0.6, kapha: 0.4)
    ),
    .init(
      id: "kapha-pitta",
      displayName: "Kapha–Pitta",
      detail: "Kapha leads",
      group: .dual,
      distribution: .init(vata: 0, pitta: 0.4, kapha: 0.6)
    ),
    .init(
      id: "vata-kapha-even",
      displayName: "Vata–Kapha",
      detail: "Even pair",
      group: .dual,
      distribution: .init(vata: 1, pitta: 0, kapha: 1)
    ),
    .init(
      id: "vata-kapha",
      displayName: "Vata–Kapha",
      detail: "Vata leads",
      group: .dual,
      distribution: .init(vata: 0.6, pitta: 0, kapha: 0.4)
    ),
    .init(
      id: "kapha-vata",
      displayName: "Kapha–Vata",
      detail: "Kapha leads",
      group: .dual,
      distribution: .init(vata: 0.4, pitta: 0, kapha: 0.6)
    ),
    .init(
      id: "sama",
      displayName: "Sama / Tridoshic",
      detail: "Balanced traditional profile",
      group: .balanced,
      distribution: .balanced
    ),
  ]

  static func option(id: String?) -> AyurvedaDeclaredTypeOption? {
    guard let id else { return nil }
    return all.first { $0.id == id }
  }
}

struct AyurvedaQuestionOption: Identifiable, Sendable {
  let dosha: AyurvedaDosha
  let text: String

  var id: AyurvedaDosha { dosha }
}

struct AyurvedaConstitutionQuestion: Identifiable, Sendable {
  let id: UUID
  let prompt: String
  let options: [AyurvedaQuestionOption]

  private static let stableIDs: [UUID] = [
    UUID(uuidString: "E55B7FD0-61FA-590E-9A5B-AC4619FFECFD")!,
    UUID(uuidString: "7694D3C7-9723-5B17-B8CD-B8D03069BCDE")!,
    UUID(uuidString: "9B554058-47DC-56C7-B168-7EC79E00DBEE")!,
    UUID(uuidString: "D5D4AA7C-9E5F-5131-A90F-CC1E202001F4")!,
    UUID(uuidString: "A4F88319-2964-5816-8A83-DD71ED8182D1")!,
    UUID(uuidString: "95AF03E2-2BB5-5AFF-A2EE-789E01E933A4")!,
    UUID(uuidString: "9BEBAE3C-E61C-542D-A5FE-FA60BE2A5FD3")!,
    UUID(uuidString: "2DAB3E14-50AA-5085-BA74-99D23EC2ED92")!,
    UUID(uuidString: "D9FAA46B-722B-5873-9AF9-3B600DEEBA3A")!,
    UUID(uuidString: "63A1A16E-CFE9-52D3-A36E-C19D95041436")!,
    UUID(uuidString: "5CB89F3E-B5B3-5E9D-ACCE-FB277CB139A5")!,
    UUID(uuidString: "D941FA41-37D2-5563-8E7F-5CA4ECF77DEA")!,
  ]

  func option(for dosha: AyurvedaDosha) -> AyurvedaQuestionOption? {
    options.first { $0.dosha == dosha }
  }

  static let all: [AyurvedaConstitutionQuestion] = {
    let rows: [(String, String, String, String)] = [
      (
        "Which has best described your build for most of your adult life?",
        "Light or thin; hard to put on weight",
        "Medium or defined; changes with effort",
        "Solid or broad; gains easily"
      ),
      (
        "Over the years, your weight has usually tended to?",
        "Fluctuate, or stay low",
        "Hold steady with effort",
        "Climb, and come off slowly"
      ),
      (
        "Your skin has generally felt?",
        "Dry or rough and cool to touch",
        "Warm and quick to flush",
        "Soft, moist and cool"
      ),
      (
        "Your hair has generally been?",
        "Fine, dry and prone to frizz",
        "Fine and prone to early greying or thinning",
        "Thick, wavy and prone to oiliness"
      ),
      (
        "Your appetite is usually?",
        "Irregular — big some days, absent on others",
        "Strong; a late meal feels uncomfortable",
        "Steady; skipping a meal is usually easy"
      ),
      (
        "After a heavy meal, you usually feel?",
        "Gassy or bloated",
        "Warm, sometimes acidic",
        "Heavy and sleepy"
      ),
      (
        "The weather you have usually felt best in is?",
        "Warm and humid",
        "Cool and breezy",
        "Warm and dry"
      ),
      (
        "Your energy through a typical day usually?",
        "Comes in bursts, then dips",
        "Feels steady and driven",
        "Starts slowly, then lasts"
      ),
      (
        "Your sleep on most nights is?",
        "Light; you wake easily",
        "Moderate; you wake, then resettle",
        "Deep and long; waking is hard"
      ),
      (
        "Your natural pace has usually been?",
        "Quick; sitting still is difficult",
        "Purposeful and focused",
        "Unhurried and steady"
      ),
      (
        "In conversation, you usually tend to be?",
        "Fast and likely to jump between subjects",
        "Precise and eager to convince",
        "Measured and happy to listen"
      ),
      (
        "Under pressure, you usually notice yourself becoming?",
        "Scattered",
        "Sharp",
        "Quiet"
      ),
    ]
    let rotations: [[AyurvedaDosha]] = [
      [.vata, .pitta, .kapha],
      [.pitta, .kapha, .vata],
      [.kapha, .vata, .pitta],
    ]

    return rows.enumerated().map { index, row in
      let textByDosha: [AyurvedaDosha: String] = [
        .vata: row.1,
        .pitta: row.2,
        .kapha: row.3,
      ]
      return AyurvedaConstitutionQuestion(
        id: stableIDs[index],
        prompt: row.0,
        options: rotations[index % rotations.count].compactMap { dosha in
          textByDosha[dosha].map {
            AyurvedaQuestionOption(dosha: dosha, text: $0)
          }
        }
      )
    }
  }()
}

struct AyurvedaCheckInQuestion: Identifiable, Sendable {
  let id: UUID
  let title: String
  let prompt: String
  let options: [AyurvedaQuestionOption]

  private static let stableIDs: [UUID] = [
    UUID(uuidString: "3C5453E3-C5C2-5F07-BF66-6216D6A6F273")!,
    UUID(uuidString: "F78C1BF5-9E5F-5436-8F61-D3DA48ADA568")!,
    UUID(uuidString: "63B070E9-0550-58B7-B963-F043789E81AD")!,
    UUID(uuidString: "BB26F518-7C8F-5AE4-82E8-0FE65278778D")!,
    UUID(uuidString: "8392FF4E-AB48-5B3B-A3A7-430ABDC1BCE7")!,
  ]

  static let all: [AyurvedaCheckInQuestion] = {
    let rows: [(String, String, String, String, String)] = [
      (
        "Sleep",
        "Over the past week or two, your sleep has felt?",
        "Light or interrupted",
        "Moderate, with some restlessness",
        "Deep, long or hard to wake from"
      ),
      (
        "Digestion",
        "Over the past week or two, after meals you have most often felt?",
        "Variable, gassy or bloated",
        "Warm or acidic",
        "Heavy or slow"
      ),
      (
        "Appetite",
        "Over the past week or two, your appetite has been?",
        "Irregular",
        "Strong and urgent",
        "Steady but easy to postpone"
      ),
      (
        "Energy",
        "Over the past week or two, your energy has been?",
        "Changeable, with bursts and dips",
        "Driven and intense",
        "Slow to start but long-lasting"
      ),
      (
        "Skin",
        "Over the past week or two, your skin has most often felt?",
        "Dry or rough",
        "Warm or sensitive",
        "Soft or oily"
      ),
    ]
    let rotations: [[AyurvedaDosha]] = [
      [.vata, .pitta, .kapha],
      [.pitta, .kapha, .vata],
      [.kapha, .vata, .pitta],
    ]
    return rows.enumerated().map { index, row in
      let textByDosha: [AyurvedaDosha: String] = [
        .vata: row.2,
        .pitta: row.3,
        .kapha: row.4,
      ]
      return AyurvedaCheckInQuestion(
        id: stableIDs[index],
        title: row.0,
        prompt: row.1,
        options: rotations[index % rotations.count].compactMap { dosha in
          textByDosha[dosha].map {
            AyurvedaQuestionOption(dosha: dosha, text: $0)
          }
        }
      )
    }
  }()
}

struct AyurvedaConstitutionResult: Equatable, Sendable {
  let distribution: AyurvedaDoshaDistribution
  let label: String
  let uncertaintyNote: String?

  static func from(answers: [AyurvedaDosha]) -> Self {
    let counts = Dictionary(grouping: answers, by: { $0 }).mapValues(\.count)
    let distribution = AyurvedaDoshaDistribution(
      vata: Double(counts[.vata, default: 0]),
      pitta: Double(counts[.pitta, default: 0]),
      kapha: Double(counts[.kapha, default: 0])
    )
    return classify(distribution: distribution, answerCount: answers.count)
  }

  static func classify(
    distribution: AyurvedaDoshaDistribution,
    answerCount: Int? = nil
  ) -> Self {
    let ordered = distribution.ordered
    let top = ordered[0]
    let second = ordered[1]
    let bottom = ordered[2]
    let oneAnswer = answerCount.map { 1.0 / Double(max(1, $0)) } ?? 0.09
    let isBalanced = top.value - bottom.value <= oneAnswer + 0.000_1

    if isBalanced {
      return Self(
        distribution: distribution,
        label: "Sama / Tridoshic",
        uncertaintyNote: "Your answers are distributed evenly across the three traditional profiles."
      )
    }

    let nearTie = top.value - second.value <= oneAnswer + 0.000_1
    let hasSecondary = second.value >= 0.25
    if nearTie || hasSecondary {
      return Self(
        distribution: distribution,
        label: "\(top.dosha.displayName)–\(second.dosha.displayName)",
        uncertaintyNote: nearTie
          ? "The leading profiles are within one answer, so the questionnaire does not separate them."
          : nil
      )
    }

    return Self(
      distribution: distribution,
      label: top.dosha.displayName,
      uncertaintyNote: nil
    )
  }
}

struct AyurvedaConstitutionDraft: Equatable, Sendable {
  let source: AyurvedaConstitutionSource
  let prakriti: AyurvedaDoshaDistribution
  let declaredTypeID: String?
  let questionnaireAnswers: [AyurvedaDosha]

  var result: AyurvedaConstitutionResult {
    if source == .questionnaire {
      return .from(answers: questionnaireAnswers)
    }
    let label = AyurvedaDeclaredTypeOption.option(id: declaredTypeID)?
      .displayName
      ?? AyurvedaConstitutionResult.classify(distribution: prakriti).label
    return AyurvedaConstitutionResult(
      distribution: prakriti,
      label: label,
      uncertaintyNote: nil
    )
  }
}

struct AyurvedaVikritiCheckIn: Codable, Equatable, Sendable {
  let answers: [AyurvedaDosha]
  let distribution: AyurvedaDoshaDistribution
  let createdAt: Date
}

struct AyurvedaConstitutionRecord: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let profileID: UUID
  var source: AyurvedaConstitutionSource
  var prakriti: AyurvedaDoshaDistribution
  var declaredTypeID: String?
  var questionnaireAnswers: [AyurvedaDosha]
  var updatedAt: Date
  var latestCheckIn: AyurvedaVikritiCheckIn?

  init(profileID: UUID, draft: AyurvedaConstitutionDraft, now: Date = .now) {
    self.id = UUID()
    self.profileID = profileID
    self.source = draft.source
    self.prakriti = draft.prakriti
    self.declaredTypeID = draft.declaredTypeID
    self.questionnaireAnswers = draft.questionnaireAnswers
    self.updatedAt = now
    self.latestCheckIn = nil
  }

  var result: AyurvedaConstitutionResult {
    if source == .questionnaire {
      return .from(answers: questionnaireAnswers)
    }
    let label = AyurvedaDeclaredTypeOption.option(id: declaredTypeID)?
      .displayName
      ?? AyurvedaConstitutionResult.classify(distribution: prakriti).label
    return AyurvedaConstitutionResult(
      distribution: prakriti,
      label: label,
      uncertaintyNote: nil
    )
  }

  func vikritiWeight(at date: Date = .now) -> Double {
    guard let latestCheckIn else { return 0 }
    let age = max(0, date.timeIntervalSince(latestCheckIn.createdAt))
    let day: TimeInterval = 86_400
    if age <= 7 * day { return 0.7 }
    if age >= 30 * day { return 0 }
    let decayProgress = (age - 7 * day) / (23 * day)
    return 0.7 * (1 - decayProgress)
  }

  func target(at date: Date = .now) -> AyurvedaDoshaDistribution {
    guard let latestCheckIn else { return prakriti }
    let alpha = vikritiWeight(at: date)
    guard alpha > 0 else { return prakriti }
    return AyurvedaDoshaDistribution(
      vata: alpha * latestCheckIn.distribution.vata
        + (1 - alpha) * prakriti.vata,
      pitta: alpha * latestCheckIn.distribution.pitta
        + (1 - alpha) * prakriti.pitta,
      kapha: alpha * latestCheckIn.distribution.kapha
        + (1 - alpha) * prakriti.kapha
    )
  }
}

extension Notification.Name {
  static let ayurvedaConstitutionDidChange = Notification.Name(
    "AyurvedaConstitutionDidChange"
  )
  static let ayurvedaConstitutionStorageDidChange = Notification.Name(
    "AyurvedaConstitutionStorageDidChange"
  )
}

@MainActor
enum AyurvedaConstitutionStore {
  private static let recordsKey = "ayura.ayurveda.constitution.records.v1"
  private static let deletionDatesKey =
    "ayura.ayurveda.constitution.deletionDates.v1"
  private static let checkInSnoozeDatesKey =
    "ayura.ayurveda.constitution.checkInSnoozeDates.v1"
  private static let activeProfileKey = "ayura.ayurveda.constitution.activeProfile"

  static func record(for profileID: UUID) -> AyurvedaConstitutionRecord? {
    records().first { $0.profileID == profileID }
  }

  static func save(
    _ draft: AyurvedaConstitutionDraft,
    for profileID: UUID
  ) {
    var allRecords = records()
    let previousCheckIn = allRecords
      .first { $0.profileID == profileID }?
      .latestCheckIn
    var record = AyurvedaConstitutionRecord(
      profileID: profileID,
      draft: draft
    )
    record.latestCheckIn = previousCheckIn
    allRecords.removeAll { $0.profileID == profileID }
    allRecords.append(record)
    persist(allRecords)
    clearDeletionDate(for: profileID)
    notify(profileID: profileID)
  }

  static func save(
    checkInAnswers: [AyurvedaDosha],
    for profileID: UUID,
    at date: Date = .now
  ) {
    guard checkInAnswers.count == AyurvedaCheckInQuestion.all.count,
      var record = record(for: profileID)
    else {
      return
    }
    let counts = Dictionary(grouping: checkInAnswers, by: { $0 })
      .mapValues(\.count)
    record.latestCheckIn = AyurvedaVikritiCheckIn(
      answers: checkInAnswers,
      distribution: AyurvedaDoshaDistribution(
        vata: Double(counts[.vata, default: 0]),
        pitta: Double(counts[.pitta, default: 0]),
        kapha: Double(counts[.kapha, default: 0])
      ),
      createdAt: date
    )
    clearCheckInSnooze(for: profileID)
    record.updatedAt = date
    var allRecords = records()
    allRecords.removeAll { $0.profileID == profileID }
    allRecords.append(record)
    persist(allRecords)
    clearDeletionDate(for: profileID)
    notify(profileID: profileID)
  }

  static func restore(
    _ calendarRecord: AyurvedaConstitutionRecord?,
    deletedAt calendarDeletionDate: Date?,
    for profileID: UUID
  ) {
    guard calendarRecord == nil
      || calendarRecord?.profileID == profileID
    else {
      return
    }

    var allRecords = records()
    let localRecord = allRecords.first { $0.profileID == profileID }
    let localDeletionDate = deletionDate(for: profileID)
    let localStateDate = [localRecord?.updatedAt, localDeletionDate]
      .compactMap { $0 }
      .max()
    let calendarStateDate = [
      calendarRecord?.updatedAt,
      calendarDeletionDate,
    ]
    .compactMap { $0 }
    .max()

    guard let calendarStateDate else { return }
    if let localStateDate, calendarStateDate <= localStateDate {
      return
    }

    allRecords.removeAll { $0.profileID == profileID }
    let recordIsLatest = calendarRecord.map { record in
      calendarDeletionDate.map { record.updatedAt > $0 } ?? true
    } ?? false
    if let calendarRecord, recordIsLatest {
      allRecords.append(calendarRecord)
      persist(allRecords)
      clearDeletionDate(for: profileID)
    } else {
      persist(allRecords)
      setDeletionDate(calendarStateDate, for: profileID)
    }

    // Restoring from the calendar should refresh local consumers without
    // scheduling an identical write back to the same metadata event.
    NotificationCenter.default.post(
      name: .ayurvedaConstitutionDidChange,
      object: profileID
    )
  }

  static func delete(profileID: UUID) {
    var allRecords = records()
    allRecords.removeAll { $0.profileID == profileID }
    persist(allRecords)
    setDeletionDate(.now, for: profileID)
    clearCheckInSnooze(for: profileID)
    if activeProfileID == profileID {
      setActiveProfile(nil)
    }
    notify(profileID: profileID)
  }

  static func setActiveProfile(_ profileID: UUID?) {
    if let profileID {
      UserDefaults.standard.set(
        profileID.uuidString,
        forKey: activeProfileKey
      )
    } else {
      UserDefaults.standard.removeObject(forKey: activeProfileKey)
    }
    NotificationCenter.default.post(
      name: .ayurvedaConstitutionDidChange,
      object: profileID
    )
  }

  static var activeProfileID: UUID? {
    UserDefaults.standard
      .string(forKey: activeProfileKey)
      .flatMap(UUID.init(uuidString:))
  }

  static func activeRecord() -> AyurvedaConstitutionRecord? {
    guard let activeProfileID else { return nil }
    return record(for: activeProfileID)
  }

  static func activeTarget(at date: Date = .now) -> AyurvedaDoshaDistribution? {
    activeRecord()?.target(at: date)
  }

  static func snoozeCheckIn(
    for profileID: UUID,
    until date: Date = .now.addingTimeInterval(7 * 86_400)
  ) {
    var dates = checkInSnoozeDates()
    dates[profileID.uuidString] = date
    persistCheckInSnoozeDates(dates)
  }

  static func checkInSnoozedUntil(for profileID: UUID) -> Date? {
    checkInSnoozeDates()[profileID.uuidString]
  }

  static func deletionDate(for profileID: UUID) -> Date? {
    deletionDates()[profileID.uuidString]
  }

  private static func records() -> [AyurvedaConstitutionRecord] {
    guard let data = UserDefaults.standard.data(forKey: recordsKey) else {
      return []
    }
    return (try? JSONDecoder().decode(
      [AyurvedaConstitutionRecord].self,
      from: data
    )) ?? []
  }

  private static func persist(_ records: [AyurvedaConstitutionRecord]) {
    guard let data = try? JSONEncoder().encode(records) else { return }
    UserDefaults.standard.set(data, forKey: recordsKey)
  }

  private static func deletionDates() -> [String: Date] {
    guard let data = UserDefaults.standard.data(forKey: deletionDatesKey) else {
      return [:]
    }
    return (try? JSONDecoder().decode(
      [String: Date].self,
      from: data
    )) ?? [:]
  }

  private static func setDeletionDate(_ date: Date, for profileID: UUID) {
    var dates = deletionDates()
    dates[profileID.uuidString] = date
    persistDeletionDates(dates)
  }

  private static func clearDeletionDate(for profileID: UUID) {
    var dates = deletionDates()
    dates.removeValue(forKey: profileID.uuidString)
    persistDeletionDates(dates)
  }

  private static func persistDeletionDates(_ dates: [String: Date]) {
    guard let data = try? JSONEncoder().encode(dates) else { return }
    UserDefaults.standard.set(data, forKey: deletionDatesKey)
  }

  private static func checkInSnoozeDates() -> [String: Date] {
    guard let data = UserDefaults.standard.data(forKey: checkInSnoozeDatesKey)
    else {
      return [:]
    }
    return (try? JSONDecoder().decode(
      [String: Date].self,
      from: data
    )) ?? [:]
  }

  private static func clearCheckInSnooze(for profileID: UUID) {
    var dates = checkInSnoozeDates()
    dates.removeValue(forKey: profileID.uuidString)
    persistCheckInSnoozeDates(dates)
  }

  private static func persistCheckInSnoozeDates(_ dates: [String: Date]) {
    guard let data = try? JSONEncoder().encode(dates) else { return }
    UserDefaults.standard.set(data, forKey: checkInSnoozeDatesKey)
  }

  private static func notify(profileID: UUID) {
    NotificationCenter.default.post(
      name: .ayurvedaConstitutionDidChange,
      object: profileID
    )
    NotificationCenter.default.post(
      name: .ayurvedaConstitutionStorageDidChange,
      object: profileID
    )
  }
}

struct AyurvedaFoodFitPresentation: Equatable, Sendable {
  enum Direction: Sendable {
    case supportive
    case mixed
    case lessSupportive
  }

  let score: Double
  let direction: Direction
  let title: String
  let explanation: String

  static func make(
    target: AyurvedaDoshaDistribution,
    vata: Int,
    pitta: Int,
    kapha: Int,
    rasa: [String],
    virya: String?,
    gunas: [String]
  ) -> Self {
    let values: [AyurvedaDosha: Int] = [
      .vata: vata,
      .pitta: pitta,
      .kapha: kapha,
    ]
    let score = target.doshaFit(vata: vata, pitta: pitta, kapha: kapha)
    let direction: Direction
    let title: String
    if score >= 0.45 {
      direction = .supportive
      title = "Supportive for your current profile"
    } else if score <= -0.45 {
      direction = .lessSupportive
      title = "Less supportive for your current profile"
    } else {
      direction = .mixed
      title = "Mixed fit for your current profile"
    }

    let supported = AyurvedaDosha.allCases
      .filter { values[$0, default: 0] < 0 }
      .sorted { target[$0] > target[$1] }
    let increased = AyurvedaDosha.allCases
      .filter { values[$0, default: 0] > 0 }
      .sorted { target[$0] > target[$1] }

    var qualityWords: [String] = []
    if let virya, !virya.isEmpty {
      qualityWords.append(virya.capitalized)
    }
    qualityWords.append(contentsOf: rasa.prefix(1).map { $0.capitalized })
    qualityWords.append(contentsOf: gunas.prefix(1).map { $0.capitalized })
    var seenQualities = Set<String>()
    qualityWords = qualityWords.filter {
      seenQualities.insert($0.lowercased()).inserted
    }
    let qualityPrefix = qualityWords.prefix(2).joined(separator: " and ")

    var actionParts: [String] = []
    if !supported.isEmpty {
      actionParts.append(
        "supports \(supported.map(\.displayName).joinedEnglish)"
      )
    }
    if !increased.isEmpty {
      actionParts.append(
        "may increase \(increased.map(\.displayName).joinedEnglish)"
      )
    }
    if actionParts.isEmpty {
      actionParts.append("is neutral across the three doshas")
    }

    let action = actionParts.joined(separator: ", but ")
    let explanation = qualityPrefix.isEmpty
      ? action.capitalized + "."
      : "\(qualityPrefix) — \(action)."
    return Self(
      score: score,
      direction: direction,
      title: title,
      explanation: explanation
    )
  }
}

private extension Array where Element == String {
  var joinedEnglish: String {
    switch count {
    case 0: ""
    case 1: self[0]
    case 2: "\(self[0]) and \(self[1])"
    default:
      dropLast().joined(separator: ", ") + ", and " + (last ?? "")
    }
  }
}

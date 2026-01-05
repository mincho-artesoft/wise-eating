struct ImportedExerciseJSON: Codable {
    let name: String
    let sets: Int
    let reps: Int
    let duration: Int
    let is_time_based: Bool
    let to_failure: Bool
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, duration, is_time_based, to_failure, unit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        name = try c.decode(String.self, forKey: .name)
        sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 0
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0

        // ✅ ключът може да липсва -> default 0
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0

        is_time_based = try c.decodeIfPresent(Bool.self, forKey: .is_time_based) ?? false
        to_failure = try c.decodeIfPresent(Bool.self, forKey: .to_failure) ?? false

        // В твоя файл unit често е "null" като string -> третирай го като nil
        let rawUnit = try c.decodeIfPresent(String.self, forKey: .unit)
        let cleaned = rawUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty, cleaned.lowercased() != "null" {
            unit = cleaned
        } else {
            unit = nil
        }
    }
}

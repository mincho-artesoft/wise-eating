
struct ImportedExerciseJSON: Codable {
    let name: String
    let sets: Int
    let reps: Int
    let duration: Int
    let is_time_based: Bool
    let to_failure: Bool
    let unit: String?
}

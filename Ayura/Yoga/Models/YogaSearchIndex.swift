import Foundation

/// The yoga tab's search, built on the same pieces as the food search: one
/// in-memory index in which every pose answers to its English name, its
/// Sanskrit name and its name in the user's language, plus its facets.
enum YogaSearchIndex {
    typealias Index = NameSearchIndex<UUID>

    /// Names in the user's language, or nil for English and for a language
    /// the bundle has no yoga names for. Same file format as the food names:
    /// yoga_name_segments.en.z and yoga_names.<language>.z, written by
    /// tools/food-names/pack.py --catalog yoga.
    nonisolated(unsafe) static var names: FoodNameLocalizer? = FoodNameLocalizer.bundled(
        for: Locale.preferredLanguages.first ?? "en",
        segmentsResource: "yoga_name_segments.en",
        namesPrefix: "yoga_names"
    )

    static func levelLabels(_ level: Int?) -> [String] {
        switch level {
        case 1: return ["Beginner", "Level 1", "Easy"]
        case 2: return ["Intermediate", "Level 2"]
        case 3: return ["Advanced", "Level 3"]
        default: return []
        }
    }

    /// A catalogue pose is stored as "Mountain Pose (Tadasana)". The title
    /// and the Sanskrit name are translated separately, so they are taken
    /// apart here; a pose whose name is only Sanskrit has no separate title.
    static func title(of item: ExerciseItem) -> String {
        guard let sanskrit = item.sanskrit, !sanskrit.isEmpty,
              item.name.hasSuffix(" (\(sanskrit))")
        else { return item.name }
        return String(item.name.dropLast(sanskrit.count + 3))
    }

    /// The name to show in the user's language, in the catalogue's own
    /// "Title (Sanskrit)" shape; nil when nothing of it is translated.
    static func localizedName(of item: ExerciseItem) -> String? {
        guard let localizer = names else { return nil }
        let title = title(of: item)
        let localTitle = localizer.localizedName(title)
        guard let sanskrit = item.sanskrit, !sanskrit.isEmpty, title != item.name else {
            return localTitle
        }
        let localSanskrit = localizer.localizedName(sanskrit)
        guard localTitle != nil || localSanskrit != nil else { return nil }
        return "\(localTitle ?? title) (\(localSanskrit ?? sanskrit))"
    }

    static func make(from items: [ExerciseItem]) -> Index {
        let localizer = names
        func local(_ text: String?) -> String? { text.flatMap { localizer?.localizedName($0) } }

        var index = Index(items.map { item in
            let title = title(of: item)
            var names = [item.name]
            if title != item.name { names.append(title) }
            if let sanskrit = item.sanskrit, !sanskrit.isEmpty { names.append(sanskrit) }
            names.append(contentsOf: [local(title), local(item.sanskrit)].compactMap { $0 })

            var facets: [String] = []
            if let family = item.family?.rawValue { facets.append(family) }
            facets.append(contentsOf: levelLabels(item.level))
            facets.append(contentsOf: item.muscleGroups.map(\.rawValue))
            if item.isWorkout { facets.append("Workout") }
            facets.append(contentsOf: facets.compactMap { local($0) })
            return Index.Entry(id: item.id, names: names, facets: facets)
        })
        index.fillerWords = ["pose", "poses", "asana", "asanas", "yoga", "exercise", "exercises"]
        return index
    }
}

extension ExerciseItem {
    /// The name to show: in the user's language when the catalogue has it.
    var displayName: String {
        YogaSearchIndex.localizedName(of: self) ?? name
    }
}

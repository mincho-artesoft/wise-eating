import Foundation

struct PracticeAudioCue: Identifiable, Hashable {
    let id: String
    let atSeconds: Double
    let text: String
    let holdSeconds: Double
    let recordedAudioURL: URL?
    let recordedDurationSeconds: Double?
}

struct PracticeAudioPlan {
    let practiceID: UUID
    let title: String
    let totalDuration: Double
    let cues: [PracticeAudioCue]
    let ambienceTrackID: String?
    let ambienceURL: URL?
    let ambienceVolume: Double
    let ambienceLoops: Bool
    let sleepSafe: Bool

    init(
        practiceID: UUID,
        title: String,
        totalDuration: Double,
        cues: [PracticeAudioCue],
        ambienceTrackID: String?,
        ambienceURL: URL?,
        ambienceVolume: Double,
        ambienceLoops: Bool,
        sleepSafe: Bool
    ) {
        precondition(totalDuration > 0)
        precondition((0...1).contains(ambienceVolume))
        precondition(cues.map(\.atSeconds) == cues.map(\.atSeconds).sorted())
        precondition(cues.allSatisfy { $0.atSeconds <= totalDuration })
        self.practiceID = practiceID
        self.title = title
        self.totalDuration = totalDuration
        self.cues = cues
        self.ambienceTrackID = ambienceTrackID
        self.ambienceURL = ambienceURL
        self.ambienceVolume = ambienceVolume
        self.ambienceLoops = ambienceLoops
        self.sleepSafe = sleepSafe
    }
}

enum PracticeVoiceMode: String, CaseIterable, Identifiable {
    case off
    case recorded

    var id: String { rawValue }
}

enum PracticeAudioDefaults {
    static let voiceMode: PracticeVoiceMode = .recorded
}

struct PracticeAmbienceTrack: Identifiable, Hashable {
    let resourceName: String
    let displayName: String
    let url: URL

    var id: String { resourceName }
}

enum PracticeAudioAssetResolver {
    private struct RecordedNarrationManifest: Decodable, Sendable {
        let format: String
        let practices: [String: RecordedNarrationPractice]
    }

    private struct RecordedNarrationPractice: Decodable, Sendable {
        let cues: [RecordedNarrationCue]
    }

    private struct RecordedNarrationCue: Decodable, Sendable {
        let audioAssetName: String
        let durationSec: Double
        let index: Int
    }

    private static let expectedNarrationFormat = "wise-eating-production-narration/v2"

    private static let recordedNarrationManifest: RecordedNarrationManifest? = {
        guard let resourceRoot = Bundle.main.resourceURL else { return nil }
        let url = resourceRoot
            .appendingPathComponent("narration", isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let manifest = try JSONDecoder().decode(
                RecordedNarrationManifest.self,
                from: Data(contentsOf: url)
            )
            guard manifest.format == expectedNarrationFormat else {
                print("⚠️ Unsupported practice narration manifest: \(manifest.format)")
                return nil
            }
            return manifest
        } catch {
            print("⚠️ Practice narration manifest could not be loaded: \(error)")
            return nil
        }
    }()

    /// Every supplied ambience file belongs to one logical catalogue mood.
    /// The practice's position inside that mood rotates through the resources,
    /// so all 36 tracks are used as defaults across the 60-practice catalogue.
    private static let defaultAmbienceResources: [String: [String]] = [
        "cedar-room": [
            "Where_Water_Meets_Wood",
            "Where_the_Bamboo_Bends",
            "Stone_and_Bamboo_Flow",
            "Bamboo_at_Dawn",
        ],
        "deep-wooden-drone": [
            "Moss_Over_The_Stream",
            "Beneath_the_Wet_Leaves",
            "Where_the_Path_Turns_Green",
        ],
        "first-light": [
            "Before_the_World_Wakes",
            "First_Light_in_the_Glade",
            "The_Glade_at_First_Light",
        ],
        "glass-meadow": [
            "Meadow_At_First_Light",
            "Clarity_at_the_Lake_s_Edge",
            "Clearing_at_Daybreak",
        ],
        "hearth": [
            "Sunlight_on_the_Current",
            "Sunlight_on_the_Falls",
            "Sunlight_on_the_Mossy_Rock",
        ],
        "morning-raga": [
            "Morning_Beneath_the_Canopy",
            "Morning_By_The_Fountain",
            "Morning_at_the_Brook",
        ],
        "ocean-floor": [
            "Tide_at_First_Light",
            "Where_the_Horizon_Rests",
            "Where_the_Water_Rests (1)",
        ],
        "open-sky": [
            "Where_The_Mountain_Breathes",
            "Where_the_Valley_Wakes",
            "Waters_of_the_Silent_Valley",
        ],
        "rain-on-stone": [
            "Rain_On_The_Broad_Leaves",
            "Rain_on_Leaves",
        ],
        "snowfall": [
            "Riverbed_At_First_Light",
            "Stillness_by_the_Bank",
            "Where_the_Current_Rests",
        ],
        "still-water": [
            "Water_Over_Smooth_Stones",
            "Where_the_Water_Meets_the_Stone",
            "Where_the_Water_Rests",
        ],
        "temple-bowls": [
            "Bamboo_at_Dawn (1)",
            "Morning_Fountain",
            "The_River_s_Breath",
        ],
    ]

    private static let catalogueOrderByTrackID: [String: [Int]] = [
        "cedar-room": [810001, 810012, 810019, 810025, 810032, 810055, 810057],
        "deep-wooden-drone": [810000, 810004, 810031, 810050],
        "first-light": [810027, 810028, 810036, 810046],
        "glass-meadow": [810015, 810038, 810048],
        "hearth": [810011, 810014, 810029, 810035, 810041, 810049, 810054],
        "morning-raga": [810006, 810021, 810051, 810053],
        "ocean-floor": [810005, 810016, 810018, 810020, 810052, 810058, 810059],
        "open-sky": [810009, 810030, 810037, 810039, 810042],
        "rain-on-stone": [810033, 810044],
        "snowfall": [810010, 810017, 810026, 810043, 810045, 810056],
        "still-water": [810003, 810013, 810022, 810024, 810034, 810047],
        "temple-bowls": [810002, 810007, 810008, 810023, 810040],
    ]

    static var mappedDefaultResourceNames: Set<String> {
        Set(defaultAmbienceResources.values.flatMap { $0 })
    }

    static var mappedDefaultResourceCount: Int {
        mappedDefaultResourceNames.count
    }

    static var recordedNarrationPracticeCount: Int {
        recordedNarrationManifest?.practices.count ?? 0
    }

    static var recordedNarrationCueCount: Int {
        recordedNarrationManifest?.practices.values.reduce(0) {
            $0 + $1.cues.count
        } ?? 0
    }

    static func hasCompleteRecordedNarration(
        practiceSlug: String,
        cueCount: Int
    ) -> Bool {
        guard let cues = recordedNarrationManifest?.practices[practiceSlug]?.cues,
              cues.count == cueCount else {
            return false
        }
        return Set(cues.map(\.index)) == Set(0..<cueCount)
            && cues.allSatisfy { bundledNarrationURL(for: $0.audioAssetName) != nil }
    }

    static func recordedNarrationCue(
        practiceSlug: String,
        index: Int
    ) -> (url: URL, durationSeconds: Double)? {
        guard let cue = recordedNarrationManifest?
            .practices[practiceSlug]?
            .cues.first(where: { $0.index == index }),
              let url = bundledNarrationURL(for: cue.audioAssetName) else {
            return nil
        }
        return (url, cue.durationSec)
    }

    static func ambienceURL(trackID: String) -> URL? {
        guard let resourceName = defaultAmbienceResources[trackID]?.first else {
            return nil
        }
        return ambienceURL(resourceName: resourceName)
    }

    static func ambienceURL(resourceName: String) -> URL? {
        resolve(
            resourceName: resourceName,
            extensions: ["m4a", "aac", "mp3", "wav"],
            subdirectories: ["Practices/Ambience", "Ambience"]
        )
    }

    static func defaultResourceName(
        for trackID: String,
        catalogNumber: Int? = nil
    ) -> String? {
        guard let resources = defaultAmbienceResources[trackID],
              !resources.isEmpty else {
            return nil
        }
        guard let catalogNumber,
              let catalogueOrder = catalogueOrderByTrackID[trackID],
              let index = catalogueOrder.firstIndex(of: catalogNumber) else {
            return resources.first
        }
        return resources[index % resources.count]
    }

    static var availableAmbienceTracks: [PracticeAmbienceTrack] {
        let extensions = Set(["mp3", "m4a", "aac", "wav"])
        var urls: [URL] = []
        for directory in ["Practices/Ambience", "Ambience"] {
            for ext in extensions {
                urls.append(
                    contentsOf: Bundle.main.urls(
                        forResourcesWithExtension: ext,
                        subdirectory: directory
                    ) ?? []
                )
            }
        }
        for ext in extensions {
            urls.append(
                contentsOf: Bundle.main.urls(
                    forResourcesWithExtension: ext,
                    subdirectory: nil
                ) ?? []
            )
        }

        let unique = Dictionary(grouping: urls, by: { $0.path }).compactMap(\.value.first)
        return unique.map { url in
            let resourceName = url.deletingPathExtension().lastPathComponent
            return PracticeAmbienceTrack(
                resourceName: resourceName,
                displayName: displayName(for: resourceName),
                url: url
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func resolve(
        resourceName: String,
        extensions: [String],
        subdirectories: [String]
    ) -> URL? {
        for directory in subdirectories {
            for ext in extensions {
                if let url = Bundle.main.url(
                    forResource: resourceName,
                    withExtension: ext,
                    subdirectory: directory
                ) {
                    return url
                }
            }
        }
        for ext in extensions {
            if let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: ext
            ) {
                return url
            }
        }
        return nil
    }

    private static func bundledNarrationURL(for relativePath: String) -> URL? {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains(".."),
              let resourceRoot = Bundle.main.resourceURL else {
            return nil
        }
        let url = resourceRoot.appendingPathComponent(relativePath, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func displayName(for resourceName: String) -> String {
        resourceName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: " (1)", with: " · alternate")
            .replacingOccurrences(of: " s ", with: "'s ")
    }
}

extension Practice {
    func makeAudioPlan(
        duration: Int,
        voiceMode: PracticeVoiceMode,
        ambienceResourceName: String?
    ) -> PracticeAudioPlan {
        let ambienceURL = ambienceResourceName.flatMap(
            PracticeAudioAssetResolver.ambienceURL(resourceName:)
        )
        return PracticeAudioPlan(
            practiceID: id,
            title: title,
            totalDuration: Double(duration),
            cues: orderedScript.enumerated().map { index, cue in
                let recordedCue = voiceMode == .recorded
                    ? PracticeAudioAssetResolver.recordedNarrationCue(
                        practiceSlug: slug,
                        index: index
                    )
                    : nil
                return PracticeAudioCue(
                    id: cue.id,
                    atSeconds: cue.atSeconds,
                    text: cue.text,
                    holdSeconds: cue.holdSeconds,
                    recordedAudioURL: recordedCue?.url,
                    recordedDurationSeconds: recordedCue?.durationSeconds
                )
            },
            ambienceTrackID: ambienceResourceName,
            ambienceURL: ambienceURL,
            ambienceVolume: ambienceVolume,
            ambienceLoops: ambienceLoops,
            sleepSafe: goals.contains("sleep")
        )
    }
}

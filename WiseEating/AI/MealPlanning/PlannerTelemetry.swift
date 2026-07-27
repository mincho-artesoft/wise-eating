import Darwin
import Foundation
import FoundationModels

actor PlannerTelemetry {
    static let shared = PlannerTelemetry()
    nonisolated static let isEnabled = ProcessInfo.processInfo.arguments.contains("-wePlannerTelemetry")

    private struct SiteStats: Codable {
        var sessions = 0
        var responds = 0
        var failedResponds = 0
        var totalMilliseconds = 0.0
    }

    private struct StageStats: Codable {
        var wallMilliseconds = 0.0
        var calls = 0
    }

    private struct SiteSummary: Codable {
        let site: String
        let sessions: Int
        let responds: Int
        let failedResponds: Int
        let totalMilliseconds: Double
        let meanMilliseconds: Double
    }

    private struct StageSummary: Codable {
        let stage: String
        let wallMilliseconds: Double
        let calls: Int
    }

    private struct JSONSummary: Codable {
        let label: String
        let totalSessions: Int
        let totalResponds: Int
        let totalFailedResponds: Int
        let sites: [SiteSummary]
        let stages: [StageSummary]
        let totalPlanWallMilliseconds: Double
        let deviceModel: String
        let iOSVersion: String
        let appleIntelligenceAvailability: String
    }

    private struct ActiveStage {
        let name: String
        let startedAt: UInt64
    }

    private static let stageOrder = [
        "interpretation",
        "context_palettes",
        "conceptual_plan",
        "goal_adjustment",
        "resolution",
        "polish",
        "deterministic_assembly",
        "narration"
    ]

    private var label = ""
    private var planStartedAt: UInt64?
    private var sites: [String: SiteStats] = [:]
    private var stages: [String: StageStats] = [:]
    private var activeStages: [ActiveStage] = []

    func reset(label: String) {
        guard Self.isEnabled else { return }
        self.label = label
        planStartedAt = Self.now()
        sites.removeAll(keepingCapacity: true)
        stages = Dictionary(
            uniqueKeysWithValues: Self.stageOrder.map { ($0, StageStats()) }
        )
        activeStages.removeAll(keepingCapacity: true)
    }

    func noteSession(site: String) {
        guard Self.isEnabled else { return }
        sites[site, default: SiteStats()].sessions += 1
    }

    func noteRespond(site: String, ok: Bool, ms: Double) {
        guard Self.isEnabled else { return }
        sites[site, default: SiteStats()].responds += 1
        sites[site, default: SiteStats()].totalMilliseconds += ms
        if !ok {
            sites[site, default: SiteStats()].failedResponds += 1
        }
        if let stage = activeStages.last?.name {
            stages[stage, default: StageStats()].calls += 1
        }
    }

    func beginStage(_ name: String) {
        guard Self.isEnabled else { return }
        activeStages.append(ActiveStage(name: name, startedAt: Self.now()))
    }

    func endStage(_ name: String) {
        guard Self.isEnabled else { return }
        guard let index = activeStages.lastIndex(where: { $0.name == name }) else {
            return
        }
        let active = activeStages.remove(at: index)
        stages[name, default: StageStats()].wallMilliseconds +=
            Self.milliseconds(from: active.startedAt, to: Self.now())
    }

    func summary() -> String {
        guard Self.isEnabled else { return "" }

        let summarizedAt = Self.now()
        let siteRows = sites.keys.sorted().map { site -> SiteSummary in
            let stats = sites[site] ?? SiteStats()
            return SiteSummary(
                site: site,
                sessions: stats.sessions,
                responds: stats.responds,
                failedResponds: stats.failedResponds,
                totalMilliseconds: stats.totalMilliseconds,
                meanMilliseconds: stats.responds == 0
                    ? 0
                    : stats.totalMilliseconds / Double(stats.responds)
            )
        }
        let stageRows = Self.stageOrder.map { stage -> StageSummary in
            let stats = stages[stage] ?? StageStats()
            let activeMilliseconds = activeStages
                .filter { $0.name == stage }
                .reduce(0.0) {
                    $0 + Self.milliseconds(from: $1.startedAt, to: summarizedAt)
                }
            return StageSummary(
                stage: stage,
                wallMilliseconds: stats.wallMilliseconds + activeMilliseconds,
                calls: stats.calls
            )
        }
        let totalSessions = siteRows.reduce(0) { $0 + $1.sessions }
        let totalResponds = siteRows.reduce(0) { $0 + $1.responds }
        let totalFailedResponds = siteRows.reduce(0) { $0 + $1.failedResponds }
        let wallMilliseconds = planStartedAt.map {
            Self.milliseconds(from: $0, to: summarizedAt)
        } ?? 0
        let availability = Self.appleIntelligenceAvailability()

        var lines = [
            "MP1-TELEMETRY: label=\(label) total sessions=\(totalSessions) total responds=\(totalResponds) total failed responds=\(totalFailedResponds)",
            "MP1-TELEMETRY: per-site (site | sessions | responds | failed | total ms | mean ms)"
        ]
        lines.append(contentsOf: siteRows.map {
            String(
                format: "MP1-TELEMETRY-SITE: %@ | %d | %d | %d | %.3f | %.3f",
                $0.site,
                $0.sessions,
                $0.responds,
                $0.failedResponds,
                $0.totalMilliseconds,
                $0.meanMilliseconds
            )
        })
        lines.append("MP1-TELEMETRY: per-stage (stage | wall-clock ms | calls attributed)")
        lines.append(contentsOf: stageRows.map {
            String(
                format: "MP1-TELEMETRY-STAGE: %@ | %.3f | %d",
                $0.stage,
                $0.wallMilliseconds,
                $0.calls
            )
        })
        lines.append(
            String(
                format: "MP1-TELEMETRY: total plan wall clock=%.3f ms device=%@ iOS=%@ Apple Intelligence=%@",
                wallMilliseconds,
                Self.deviceModel(),
                ProcessInfo.processInfo.operatingSystemVersionString,
                availability
            )
        )

        let jsonSummary = JSONSummary(
            label: label,
            totalSessions: totalSessions,
            totalResponds: totalResponds,
            totalFailedResponds: totalFailedResponds,
            sites: siteRows,
            stages: stageRows,
            totalPlanWallMilliseconds: wallMilliseconds,
            deviceModel: Self.deviceModel(),
            iOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appleIntelligenceAvailability: availability
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(jsonSummary))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{\"error\":\"telemetry encoding failed\"}"
        lines.append("MP1-TELEMETRY-JSON \(json)")
        return lines.joined(separator: "\n")
    }

    nonisolated private static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    nonisolated private static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    nonisolated private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    nonisolated private static func appleIntelligenceAvailability() -> String {
        guard #available(iOS 26.0, *) else { return "unavailable:iOS-before-26" }
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable:\(String(describing: reason))"
        @unknown default:
            return "unknown"
        }
    }
}

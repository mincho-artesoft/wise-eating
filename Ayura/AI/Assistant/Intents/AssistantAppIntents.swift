import AppIntents
import Foundation
import SwiftData

/// Siri and Shortcuts reach the same tools as the assistant screen. Logging
/// asks for confirmation before anything is written.
enum AssistantIntentSupport {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notReady, noProfile

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .notReady: "The app is still preparing its food catalogue. Try again in a moment."
            case .noProfile: "Create a profile in the app and allow calendar access first."
            }
        }
    }

    @MainActor
    static func toolbox() async throws -> AssistantToolbox {
        var context = GlobalState.modelContext
        for _ in 0..<40 where context == nil {
            try await Task.sleep(for: .milliseconds(250))
            context = GlobalState.modelContext
        }
        guard let context else { throw Failure.notReady }
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        let active = AyurvedaConstitutionStore.activeProfileID
        guard let profile = profiles.first(where: { $0.id == active }) ?? profiles.first else {
            throw Failure.noProfile
        }
        return AssistantToolbox(data: AssistantLiveDataSource(profile: profile, container: context.container))
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Adds what you ate to today's meals in Ayurveda & Asana Yoga.")

    @Parameter(title: "What did you eat?", requestValueDialog: "What did you eat?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolbox = try await AssistantIntentSupport.toolbox()
        let engine = OnDeviceEngine()
        let reply = try await engine.respond(to: AssistantTurn(text: text), toolbox: toolbox)

        guard let action = toolbox.pending.first,
              case let .logFoods(_, meal, items) = action.payload else {
            return .result(dialog: IntentDialog(stringLiteral: reply.text))
        }
        let list = items.map { "\($0.name) \(DietaryUnits.format($0.grams)) g" }.joined(separator: ", ")
        var question = String(localized: "Add to \(meal): \(list)?")
        if let report = action.report, !report.violations.isEmpty {
            question += " " + report.violations.map(\.message).joined(separator: " ")
        }
        try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: question)))
        let result = await toolbox.confirm(action.id)
        return .result(dialog: IntentDialog(stringLiteral: result?.message ?? String(localized: "Nothing was logged.")))
    }
}

struct WhatDidIEatTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What Did I Eat Today"
    static let description = IntentDescription("Tells you what is logged for today and the day's calories and protein.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolbox = try await AssistantIntentSupport.toolbox()
        let day = OnDeviceEngine.object(await toolbox.call("get_day", arguments: "{\"date\":\"today\"}"))
        return .result(dialog: IntentDialog(stringLiteral: OnDeviceEngine.describeDay(day)))
    }
}

struct AyuraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife")
        AppShortcut(
            intent: WhatDidIEatTodayIntent(),
            phrases: [
                "What did I eat today in \(.applicationName)",
                "Today's meals in \(.applicationName)",
            ],
            shortTitle: "What I Ate Today",
            systemImageName: "list.bullet")
    }
}

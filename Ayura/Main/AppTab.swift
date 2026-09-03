import Foundation

enum AppTab: Int, CaseIterable, Identifiable {
    case nutrition, training, foods, calendar, storage, shoppingList, aiGenerate, search, analytics, exercises, nodes, practices//, test

    var id: UUID {
        precondition(
            Self.stableIDs.count == Self.allCases.count,
            "AppTab stableIDs must match allCases"
        )
        return Self.stableIDs[rawValue]
    }

    static var stableIDCountMatchesCases: Bool {
        stableIDs.count == allCases.count
    }

    private static let stableIDs: [UUID] = [
        UUID(uuidString: "8E6BDEA8-95E3-5958-8A0C-CB0986E87172")!,
        UUID(uuidString: "89D5DC93-F335-5562-BFFA-2CEF27618724")!,
        UUID(uuidString: "ECA8144F-7E38-5235-8375-4555346D2BB7")!,
        UUID(uuidString: "CD181048-C149-5415-8DB6-1BCBAC5CB898")!,
        UUID(uuidString: "AAEA6848-55C6-5D8B-9160-AF55D1C188F6")!,
        UUID(uuidString: "773609EF-991F-5624-BF3A-2E2429FE9BA2")!,
        UUID(uuidString: "2EEC9FA6-2791-5EC1-B5B5-88E072E14A7E")!,
        UUID(uuidString: "EE56B20A-2B8F-5D6E-A405-FD0ED6888818")!,
        UUID(uuidString: "D9741028-116F-5EDC-97D7-8C1DC0A9B5FC")!,
        UUID(uuidString: "AB722EAD-A174-50B3-A82D-C8D31DF30527")!,
        UUID(uuidString: "72E9E511-2127-514F-98AD-CA95ED8473FE")!,
        // uuid5(seed-identities/v1, "app-tab:practices")
        UUID(uuidString: "F4728EEB-7771-57B2-8B06-48CA4A4A654C")!,
    ]

    var title: String {
        switch self {
        case .nutrition: "Nutrition"
        case .training: "Training"
        case .foods: "Foods"
        case .calendar: "Calendar"
        case .storage: "Storage"
        case .shoppingList: "Shopping List"
        case .analytics: "Analytics"
        case .search: "Search"
        case .exercises: "Exercises"
        case .aiGenerate: "Generate"
        case .nodes: "Notes"
        case .practices: "Practices"
//        case .test: "test"
        }
    }

    var iconName: String {
        switch self {
        case .nutrition: "nutrition_icon"
        case .training: "training_icon"
        case .foods: "fork.knife"
        case .calendar: "calendar_icon"
        case .storage: "storage_icon"
        case .shoppingList:  "shoppingList_icon"
        case .analytics: "chart.bar.xaxis"
        case .search: "search_icon"
        case .exercises: "figure.run"
        case .aiGenerate: "aiGenerate_icon"
        case .nodes: "shareplay"
        case .practices: "practices_icon"
//        case .test: "search_icon"
        }
    }
}

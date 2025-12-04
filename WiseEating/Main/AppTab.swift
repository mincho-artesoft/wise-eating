import Foundation

enum AppTab: Int, CaseIterable, Identifiable {
    case nutrition, training, foods, calendar, storage, shoppingList, aiGenerate, search, analytics, exercises, nodes, badges//, test

    var id: Int { self.rawValue }

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
        case .badges: "Badges"
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
        case .badges: "rosette"
//        case .test: "search_icon"
        }
    }
}

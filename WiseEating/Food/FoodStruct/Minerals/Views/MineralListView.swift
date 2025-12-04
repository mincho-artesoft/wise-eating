import SwiftUI
import SwiftData

struct MineralListView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: – Queries & dependencies
    @Query private var minerals: [Mineral]
    @Environment(\.modelContext) private var modelContext
    var profile: Profile?

    // MARK: – UI state
    @State private var searchText: String = "" // Тази променлива остава, в случай че добавите поле за търсене

    // MARK: – Demographic label helper
    private func demographicString(for profile: Profile) -> String {
        // ... (съдържанието на функцията е непроменено)
        let isFemale = profile.gender.lowercased().hasPrefix("f")
        if isFemale {
            if profile.isPregnant  { return Demographic.pregnantWomen }
            if profile.isLactating { return Demographic.lactatingWomen }
        }

        let months = Calendar.current.dateComponents([.month],
                                                     from: profile.birthday,
                                                     to: Date()).month ?? 0
        if months < 6  { return Demographic.babies0_6m }
        if months < 12 { return Demographic.babies7_12m }

        switch profile.age {
        case 1..<4:   return Demographic.children1_3y
        case 4..<9:   return Demographic.children4_8y
        case 9..<14:  return Demographic.children9_13y
        case 14..<19: return isFemale
            ? Demographic.adolescentFemales14_18y
            : Demographic.adolescentMales14_18y
        default:
            if isFemale {
                return profile.age <= 50
                    ? Demographic.adultWomen19_50y
                    : Demographic.adultWomen51plusY
            } else {
                return profile.age <= 50
                    ? Demographic.adultMen19_50y
                    : Demographic.adultMen51plusY
            }
        }
    }

    private var filteredMinerals: [Mineral] {
        // ... (съдържанието на променливата е непроменено)
        if searchText.isEmpty {
            return minerals
        }
        return minerals.filter { mineral in
            mineral.name.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        // ПРОМЯНА: Премахваме VStack и GeometryReader. Използваме ScrollView.
        ScrollView(showsIndicators: false) {
            // ПРОМЯНА: LazyVStack вместо List за персонализиран изглед на редовете.
            LazyVStack(spacing: 12) {
                ForEach(filteredMinerals) { mineral in
                    MineralRowView(
                        mineral: mineral,
                        demographic: profile.map(demographicString)
                    )                    
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            Spacer(minLength: 150)

        }
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                    .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                    .init(color: .clear, location: 0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Забележка: Searchable може да се добави тук, ако решите да имате поле за търсене
        // .searchable(text: $searchText, prompt: "Search Minerals")
        .background(Color.clear)
    }
}

import SwiftUI
import SwiftData

struct VitaminListView: View {
    // MARK: – Queries & dependencies
    @Query private var vitamins: [Vitamin]
    @Environment(\.modelContext) private var modelContext
    var profile: Profile?

    // ПРОМЯНА: Добавям EffectManager за достъп до глобалния цвят, ако е нужен
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Приемаме, че тази computed property съществува някъде във вашия код
    private var filteredVitamins: [Vitamin] {
        // Тук може да има логика за филтриране, ако е нужна
        return vitamins
    }

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(filteredVitamins) { vitamin in
                    VitaminRowView(
                        vitamin: vitamin,
                        demographic: profile.map(demographicString)
                    )
                }
                
            }
            .padding(.horizontal) // Добавяме хоризонтално отстояние за картите
            .padding(.top, 8)       // Малко отстояние от горния край
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
        .background(Color.clear) // Гарантираме, че фонът е прозрачен
    }
}

import SwiftUI
import SwiftData

struct ExerciseRowView: View {
    @Bindable var item: ExerciseItem
    
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // --- НАЧАЛО НА ПРОМЯНАТА (1/2): Добавяме изчисляемо свойство за текста ---
    private var descriptionText: String? {
        if item.isWorkout {
            guard let links = item.exercises, !links.isEmpty else {
                // Ако е тренировка, но няма упражнения, показваме нейното описание
                return item.exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            }
            // Взимаме имената на първите 3 упражнения
            let first = links.prefix(3).compactMap { $0.exercise?.name }
            var text = first.joined(separator: ", ")
            
            // Добавяме многоточие, ако има повече от 3
            if links.count > 3 {
                text += "..."
            }
            return text.nilIfEmpty()
        } else {
            // За обикновени упражнения показваме описанието
            return item.exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (1/2) ---

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                image
                    .frame(width: 80, height: 80)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .lineLimit(2)
                        
                        Spacer()

                        Button(action: {
                            withAnimation(.spring()) {
                                item.isFavorite.toggle()
                            }
                            // Запис в същия контекст, от който идват моделите в списъка.
                            do {
                                try modelContext.save()
                                // Пращаме нотификация СЛЕД успешен save
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: .exerciseFavoriteToggled, object: item)
                                }
                            } catch {
                                print("❌ Грешка при запис на isFavorite: \(error.localizedDescription)")
                                withAnimation(.spring()) {
                                    item.isFavorite.toggle() // revert on failure
                                }
                            }
                        }) {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.title3)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .animation(.spring(), value: item.isFavorite)

                    // --- НАЧАЛО НА ПРОМЯНАТА (2/2): Използваме новото свойство тук ---
                    if let description = descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .lineLimit(2)
                    }
                    // --- КРАЙ НА ПРОМЯНАТА (2/2) ---
                }
                .layoutPriority(1)
            }

            let sports = item.sports ?? []
            let muscleGroups = item.muscleGroups
            
            if !sports.isEmpty || !muscleGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !sports.isEmpty {
                        ChipScrollView(title: "Related Sports", items: sports, textColor: effectManager.currentGlobalAccentColor)
                    }
                    if !muscleGroups.isEmpty {
                        ChipScrollView(title: "Primary Muscles", items: muscleGroups, textColor: effectManager.currentGlobalAccentColor)
                    }
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private var image: some View {
        if let photoData = item.photo, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage).resizable().scaledToFill().clipShape(Circle())
        } else if let assetName = item.assetImageName, let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage).resizable().scaledToFill().clipShape(Circle())
        } else {
            Image(systemName: "dumbbell.fill")
                .resizable().scaledToFit().padding(20)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

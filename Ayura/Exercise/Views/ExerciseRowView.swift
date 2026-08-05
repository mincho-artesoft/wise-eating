import SwiftUI
import SwiftData

struct ExerciseRowView: View {
    @Bindable var item: ExerciseItem
    
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    private var descriptionText: String? {
        // Допълнителна защита, макар че главната е в body
        if item.isDeleted { return nil }
        
        if item.isWorkout {
            guard let links = item.exercises, !links.isEmpty else {
                return item.exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            }
            let first = links.prefix(3).compactMap { $0.exercise?.name }
            var text = first.joined(separator: ", ")
            
            if links.count > 3 {
                text += "..."
            }
            return text.nilIfEmpty()
        } else {
            return item.exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        }
    }

    var body: some View {
        // ✅ FIX: Тази проверка предотвратява краша при изтриване.
        // Ако обектът е изтрит или няма контекст, не рендираме нищо.
        if item.isDeleted || item.modelContext == nil {
            EmptyView()
        } else {
            // Целият UI код влиза в else блока
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseThumbnailView(
                        item: item,
                        size: 80,
                        cornerRadius: 40
                    )
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
                                do {
                                    try modelContext.save()
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(name: .exerciseFavoriteToggled, object: item)
                                    }
                                } catch {
                                    print("❌ Грешка при запис на isFavorite: \(error.localizedDescription)")
                                    withAnimation(.spring()) {
                                        item.isFavorite.toggle()
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

                        if let description = descriptionText, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .lineLimit(2)
                        }

                        ExerciseAyurvedaSearchResultChips(item: item)
                    }
                    .layoutPriority(1)
                }

                let muscleGroups = item.muscleGroups
                
                if !muscleGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ChipScrollView(title: "Primary Muscles", items: muscleGroups, textColor: effectManager.currentGlobalAccentColor)
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
}

/// Shared row thumbnail for exercises and workouts. Keeping all row imagery
/// behind this view means a future video-frame source only needs to be added to
/// `ExerciseItem.exerciseImage()` once.
struct ExerciseThumbnailView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let item: ExerciseItem
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let uiImage = item.exerciseImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.15))

                    Image(systemName: "figure.yoga")
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

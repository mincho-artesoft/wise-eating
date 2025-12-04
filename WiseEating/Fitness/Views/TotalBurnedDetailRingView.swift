// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Fitness/Views/TotalBurnedDetailRingView.swift
import SwiftUI
import SwiftData

struct TotalBurnedDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    let totalCalories: Double
    let trainings: [Training]
    let profile: Profile
    let onDismiss: () -> Void
    
    // --- START OF MODIFICATION: Add state for filtering ---
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    
    private var allMuscleGroups: [MuscleGroup] {
        MuscleGroup.allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
    private var allExercisesOfTheDay: [(exercise: ExerciseItem, duration: Double)] {
        let all = trainings
            .flatMap { training in
                training.exercises(using: modelContext)
            }
            .map { (exercise: $0.key, duration: $0.value) }

        guard let group = selectedMuscleGroup else {
            return all.sorted { $0.exercise.name < $1.exercise.name }
        }

        return all
            .filter { $0.exercise.muscleGroups.contains(group) }
            .sorted { $0.exercise.name < $1.exercise.name }
    }
    
    // --- END OF MODIFICATION ---

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (unchanged)
            HStack {
                Button("Close", action: onDismiss)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                Spacer()
                Text("Total Burned Today").font(.headline)
                Spacer()
                Button("Close") {}.hidden().padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            VStack(spacing: 16) {
                summaryCard
                    .padding(.horizontal)
            }
          
            
            ScrollView(showsIndicators: false) {
                
                VStack(spacing: 16) {
                    collapsedMuscleGroups
                        .padding(.top, 16)
                    
                    listHeader
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    if allExercisesOfTheDay.isEmpty {
                        // --- START OF MODIFICATION: Improved empty state ---
                        let message = selectedMuscleGroup == nil ? "No exercises have been logged for today." : "No exercises found for the selected muscle group."
                        ContentUnavailableView(selectedMuscleGroup == nil ? "No Exercises Logged" : "No Results", systemImage: "dumbbell", description: Text(message))
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .padding(.vertical, 40)
                            .glassCardStyle(cornerRadius: 15)
                        // --- END OF MODIFICATION ---
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(allExercisesOfTheDay, id: \.exercise.id) { item in
                                ExerciseCalorieRowView(
                                    exercise: item.exercise,
                                    duration: item.duration,
                                    profile: profile
                                )
                            }
                        }
                    }
                    Spacer(minLength: 150)
                }
                .padding()
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
        }
        Spacer()
    }
    
    private var summaryCard: some View {
        HStack {
            Text("Total Burned Today:")
            Spacer()
            Text("\(totalCalories, specifier: "%.0f") kcal")
        }
        .font(.headline)
        .padding()
        .glassCardStyle(cornerRadius: 15)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }
    
    private var listHeader: some View {
        Text(selectedMuscleGroup == nil ? "All Exercises Today" : "Filtered Exercises")
            .font(.headline)
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // --- START OF MODIFICATION: Copied helper properties and views from TrainingView ---
    private let ringsPerRow:   Int     = 4
    private let ringSize:      CGFloat = 40
    private let ringSpacing:   CGFloat = 10
    private let labelSpacing:  CGFloat = 6
    private let ringPadding:   CGFloat = 6
    private let pageGap: CGFloat = 0

    private var ringCellWidth:  CGFloat { ringSize + ringPadding * 6 }
    private var labelHeight:    CGFloat { ringSize * 0.18 * 1.25 }
    private var ringCellHeight: CGFloat {
        ringSize + labelSpacing
        + ringSize * 1.25 * 2
        + ringPadding * 2 + 4
    }

    
    @ViewBuilder
    private func muscleCardButton(for group: MuscleGroup) -> some View {
        let isSelected = (selectedMuscleGroup == group)

        Button {
            withAnimation(.easeInOut) {
                selectedMuscleGroup = isSelected ? nil : group
            }
        } label: {
            VStack(spacing: 4) {
                if let uiImage = UIImage(named: group.rawValue) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: ringCellHeight * 0.85)

                    Text(group.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .lineLimit(1)
                } else {
                    Text(group.rawValue)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: ringCellWidth, height: ringCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCardStyle(cornerRadius: 15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(
                    isSelected ? effectManager.currentGlobalAccentColor : .clear,
                    lineWidth: 2.5
                )
        )
        .animation(.easeInOut, value: isSelected)
    }

    @ViewBuilder
    private var collapsedMuscleGroups: some View {
        let items = allMuscleGroups
        let pages: [[MuscleGroup]] = stride(from: 0, to: items.count, by: ringsPerRow)
            .map { Array(items[$0 ..< min($0 + ringsPerRow, items.count)]) }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pageGap) {
                ForEach(pages.indices, id: \.self) { idx in
                    let cols = Array(
                        repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing),
                        count: ringsPerRow
                    )
                    LazyVGrid(columns: cols, spacing: ringSpacing) {
                        ForEach(pages[idx]) { group in
                            muscleCardButton(for: group)
                        }
                    }
                    .frame(height: ringCellHeight)
                    .containerRelativeFrame(.horizontal)
                    .contentShape(Rectangle())
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .frame(height: ringCellHeight)
    }
    // --- END OF MODIFICATION ---
}

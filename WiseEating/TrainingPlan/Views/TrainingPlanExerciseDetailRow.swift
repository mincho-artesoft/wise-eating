import SwiftUI

struct TrainingPlanExerciseDetailRow: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Входни данни
    let link: TrainingPlanExercise
    let profile: Profile
    
    // Състояние за разгъване
    @State private var isExpanded: Bool = false
    
    // Помощни променливи
    private var exercise: ExerciseItem? { link.exercise }
    private var duration: Double { link.durationMinutes }
    
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var weightUnit: String { isImperial ? "lbs" : "kg" }
    
    private var caloriesBurned: Double {
        guard let ex = exercise, let met = ex.metValue else { return 0 }
        let cpm = (met * 3.5 * profile.weight) / 200.0
        return cpm * duration
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ROW (Кликаем) ---
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    exerciseImage
                        .frame(width: 60, height: 60)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise?.name ?? "Unknown")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(2)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("\(caloriesBurned, specifier: "%.0f") kcal")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                            
                            Text("\(link.sets.count) sets")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 8)
                    
                    HStack(spacing: 6) {
                        Text(String(format: "%.0f", duration))
                            .font(.subheadline)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                        
                        Text("min")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .padding(.leading, 4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // --- EXPANDED SETS ---
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        .padding(.vertical, 8)
                    
                    if link.sets.isEmpty {
                        Text("No sets detailed.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                            .padding(.bottom, 4)
                    } else {
                        // Сортираме по orderIndex
                        let sortedSets = link.sets.sorted { $0.orderIndex < $1.orderIndex }
                        
                        ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
                                    .frame(width: 50, alignment: .leading)
                                
                                Spacer()
                                
                                // REPS OR FAILURE OR TIME TEXT
                                if set.isToFailure {
                                      HStack(spacing: 4) {
                                          Text("To Failure")
                                      }
                                      .foregroundStyle(.orange)
                                  } else {
                                      if let val = set.reps {
                                          // ✅ ПРОМЯНА: Проверка за isTimeBased и timeUnit
                                          let unitText: String = {
                                              if set.isTimeBased {
                                                  return set.timeUnit == .minutes ? "min" : "sec"
                                              }
                                              return "reps"
                                          }()
                                          
                                          Text("\(val) \(unitText)")
                                              .font(.subheadline)
                                              .foregroundStyle(effectManager.currentGlobalAccentColor)
                                      } else {
                                          Text("-")
                                              .font(.caption)
                                              .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
                                      }
                                  }
                                Spacer()
                                
                                // Weight
                                if let w = set.weight {
                                    let displayWeight = isImperial ? UnitConversion.kgToLbs(w) : w
                                    Text(String(format: "%.1f %@", displayWeight, weightUnit))
                                        .font(.subheadline)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                                        .frame(minWidth: 60, alignment: .trailing)
                                } else {
                                    Text("-")
                                        .font(.caption)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
                                        .frame(minWidth: 60, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                index % 2 == 0
                                ? effectManager.currentGlobalAccentColor.opacity(0.05)
                                : Color.clear
                            )
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private var exerciseImage: some View {
        if let data = exercise?.photo, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let asset = exercise?.assetImageName, let uiImage = UIImage(named: asset) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Image(systemName: "dumbbell.fill")
                .resizable()
                .scaledToFit()
                .padding(12)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

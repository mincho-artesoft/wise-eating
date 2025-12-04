import SwiftUI
import SwiftData
import EventKit

struct SelectedExerciseRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Input
    let exercise: ExerciseItem
    let duration: Double
    let profile: Profile
    var onDurationChanged: (Double) -> Void
    var onDelete: () -> Void

    // MARK: - Focus State
    @FocusState.Binding var focusedField: TrainingView.FocusableField?
    let focusCase: TrainingView.FocusableField

    @Binding var expandedExerciseID: ExerciseItem.ID?

    // MARK: - Internal State
    @State private var textValue: String
    
    @State private var showFullText: Bool

    private var isExpanded: Bool {
        expandedExerciseID == exercise.id
    }
    
    private var isFocused: Bool { focusedField == focusCase }

    // MARK: - Computed Properties
    private var caloriesBurned: Double {
        guard let met = exercise.metValue else { return 0 }
        let cpm = (met * 3.5 * profile.weight) / 200.0 // Calories per minute
        return cpm * duration
    }

    // MARK: - Initializer
    init(
        exercise: ExerciseItem,
        duration: Double,
        profile: Profile,
        onDurationChanged: @escaping (Double) -> Void,
        onDelete: @escaping () -> Void,
        focusedField: FocusState<TrainingView.FocusableField?>.Binding,
        focusCase: TrainingView.FocusableField,
        expandedExerciseID: Binding<ExerciseItem.ID?>
    ) {
        self.exercise = exercise
        self.duration = duration
        self.profile = profile
        self.onDurationChanged = onDurationChanged
        self.onDelete = onDelete
        self._focusedField = focusedField
        self.focusCase = focusCase
        self._expandedExerciseID = expandedExerciseID
        self._textValue = State(initialValue: String(format: "%.0f", duration))
        self._showFullText = State(initialValue: expandedExerciseID.wrappedValue == exercise.id)
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 12) {
            exerciseImage
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .if(showFullText) { view in
                        view.fixedSize(horizontal: false, vertical: true)
                    } else: { view in
                        view.lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isExpanded {
                            // СВИВАНЕ
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showFullText = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now()) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    expandedExerciseID = nil
                                }
                            }
                        } else {
                            // РАЗГЪВАНЕ
                            withAnimation(.easeInOut(duration: 0.3)) {
                                expandedExerciseID = exercise.id
                            }
                        }
                    }
                    .onChange(of: isExpanded) { _, isNowExpanded in
                        if isNowExpanded {
                            DispatchQueue.main.asyncAfter(deadline: .now()) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showFullText = true
                                }
                            }
                        } else {
                            showFullText = false
                        }
                    }

                // +++ НАЧАЛО НА ПРОМЯНАТА +++
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(caloriesBurned, specifier: "%.0f") kcal")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    
                    if let nodes = exercise.nodes, !nodes.isEmpty {
                        HStack(spacing: 4) {
                            Text("Nodes: \(nodes.count)")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
                    }
                }
                .padding(.top, 2)
                // +++ КРАЙ НА ПРОМЯНАТА +++
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ConfigurableTextField(
                    title: "min",
                    value: $textValue,
                    type: .integer,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: $focusedField,
                    fieldIdentifier: focusCase
                )
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                Text("min")
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .onChange(of: textValue) { _, newText in
            if let newDuration = Double(newText) {
                onDurationChanged(newDuration)
            } else if newText.isEmpty {
                onDurationChanged(0)
            }
        }
        .onChange(of: isFocused) { _, isNowFocused in
            if !isNowFocused {
                formatAndCommit()
            }
        }
        .onChange(of: duration) { _, newDuration in
            let currentTextAsDouble = Double(textValue) ?? 0.0
            if abs(currentTextAsDouble - newDuration) > 0.1 {
                textValue = String(format: "%.0f", newDuration)
            }
        }
    }

    // MARK: - Subviews & Helpers
    @ViewBuilder
    private var exerciseImage: some View {
        if let photoData = exercise.photo, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let assetName = exercise.assetImageName, let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Image(systemName: "dumbbell.fill")
                .resizable()
                .scaledToFit()
                .padding(15)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
        }
    }

    private func formatAndCommit() {
        let newDuration = Double(textValue) ?? duration
        let clampedDuration = max(1, min(newDuration, 999))
        
        textValue = String(format: "%.0f", clampedDuration)
        
        if abs(clampedDuration - duration) > 0.1 {
            onDurationChanged(clampedDuration)
        }
    }
}

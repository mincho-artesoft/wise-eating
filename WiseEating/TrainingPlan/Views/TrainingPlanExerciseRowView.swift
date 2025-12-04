import SwiftUI

struct TrainingPlanExerciseRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    @Binding var link: TrainingPlanExercise
    @FocusState.Binding var focusedField: TrainingPlanEditorView.FocusableField?
    let focusCase: TrainingPlanEditorView.FocusableField
    var onDelete: () -> Void

    @State private var textValue: String

    private var item: ExerciseItem? { link.exercise }
    private var duration: Double { link.durationMinutes }

    init(
        link: Binding<TrainingPlanExercise>,
        focusedField: FocusState<TrainingPlanEditorView.FocusableField?>.Binding,
        focusCase: TrainingPlanEditorView.FocusableField,
        onDelete: @escaping () -> Void
    ) {
        self._link = link
        self._focusedField = focusedField
        self.focusCase = focusCase
        self.onDelete = onDelete
        self._textValue = State(initialValue: String(format: "%.0f", link.wrappedValue.durationMinutes))
    }

    var body: some View {
        HStack {
            Text(item?.name ?? "Unknown")
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .fixedSize()
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                Text("min")
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .buttonStyle(.borderless)
                .tint(.red)
            }
        }
        .padding(12)
        .glassCardStyle(cornerRadius: 20)
        .onChange(of: textValue) { _, newText in
            if let newDuration = Double(newText) {
                link.durationMinutes = newDuration
            } else if newText.isEmpty {
                link.durationMinutes = 0
            }
        }
        .onChange(of: link.durationMinutes) { _, newDuration in
            let currentTextAsDouble = Double(textValue) ?? 0.0
            if abs(currentTextAsDouble - newDuration) > 0.1 {
                textValue = String(format: "%.0f", newDuration)
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus != focusCase {
                let clampedDuration = max(1, min(link.durationMinutes, 999))
                textValue = String(format: "%.0f", clampedDuration)
                link.durationMinutes = clampedDuration
            }
        }
    }
}

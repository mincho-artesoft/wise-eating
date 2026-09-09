import SwiftUI

struct SelectableExerciseRowNode: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let exercise: ExerciseItem
    let isSelected: Bool
    
    // Същият „външен“ диаметър като donutD при SelectableFoodRowNode
    private let central: CGFloat = 60
    private let ringT:   CGFloat = 6
    private let canalT:  CGFloat = 6
    private var imageDiameter: CGFloat { central + 2 * (ringT + canalT) } // 84

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            HStack(spacing: 12) {
                // 👇 размерът вече е като при графиката (84x84)
                ExerciseThumbnailView(
                    item: exercise,
                    size: imageDiameter,
                    cornerRadius: imageDiameter / 2
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                
                Spacer()
            }
        }
        .frame(height: 95)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2)
        )
    }
    
}

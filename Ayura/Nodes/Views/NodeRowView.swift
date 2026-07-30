import SwiftUI

struct NodeRowView: View {
    let node: Node
    @ObservedObject var effectManager = EffectManager.shared

    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2): Добавяме изчисляемо свойство за форматиране на датата +++
    private var formattedNodeDate: String {
        let formatter = DateFormatter()
        if !GlobalState.dateFormat.isEmpty {
            formatter.dateFormat = GlobalState.dateFormat
        } else {
            // КОРЕКЦИЯ: .abbreviated е заменено с .medium
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }
        return formatter.string(from: node.date)
    }
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // +++ НАЧАЛО НА ПРОМЯНАТА (2/2): Използваме новото свойство +++
                Text(formattedNodeDate)
                // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                Spacer()
            }

            if let text = node.textContent, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(4)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            
            if !(node.linkedFoods?.isEmpty ?? true) || !(node.linkedExercises?.isEmpty ?? true) {
                Divider().background(effectManager.currentGlobalAccentColor.opacity(0.3))
            }
            
            if let foods = node.linkedFoods, !foods.isEmpty {
                linkedItemsSection(title: "Foods", items: foods.map { $0.name }, icon: "fork.knife")
            }
            
            if let exercises = node.linkedExercises, !exercises.isEmpty {
                linkedItemsSection(title: "Exercises", items: exercises.map { $0.name }, icon: "dumbbell.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func linkedItemsSection(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
            
            Text(items.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
    }
}

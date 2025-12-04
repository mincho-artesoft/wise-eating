import SwiftUI

struct GoalSelectionView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var selectedGoal: Goal?
    @State public var isStyle = false
    var body: some View {
        VStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Goal.allCases) { goal in
                        Button {
                            withAnimation(.spring()) {
                                selectedGoal = goal
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: goal.systemImageName)
                                    .font(.title2)
                                    .frame(width: 40)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)

                                VStack(alignment: .leading) {
                                    Text(goal.title)
                                        .font(.headline)
                                    Text(goal.description)
                                        .font(.subheadline)
                                        .opacity(0.8)
                                }
                                .foregroundColor(effectManager.currentGlobalAccentColor)

                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                            .glassCardStyle(cornerRadius: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(selectedGoal == goal ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2.5)
                            )
//                            .if(isStyle) { $0.padding(.vertical, 3)}
                            .padding(5)
                        }
                        .buttonStyle(.plain)
                    }
                    if isStyle {
                        Color.clear.frame(height: 150)
                    }
                }
                .if(isStyle) { $0.padding(.horizontal) }
            }
            .scrollContentBackground(.hidden)
        }
       
    }
}


import SwiftUI

struct TrainingRowsView: View {
    let exercises: [(ExerciseItem, Double)]
    let profile: Profile
    @ObservedObject var pageState: PageState
    @State private var lastAction = Date()
    private let autoAdvanceAfter: TimeInterval = 10

    private var pageCount: Int {
        exercises.count > 1 ? exercises.count + 1 : exercises.count
    }

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $pageState.pageIndex) {
                if pageCount > 1 {
                    TrainingSummaryRowEventView(exercises: exercises, profile: profile)
                        .frame(maxWidth: geo.size.width, alignment: .leading)
                        .tag(0)
                }
                
                ForEach(Array(exercises.enumerated()), id: \.1.0.id) { idx, pair in
                    ExerciseRowEventView(exercise: pair.0, duration: pair.1, profile: profile)
                        .frame(maxWidth: geo.size.width, alignment: .leading)
                        .tag(pageCount > 1 ? idx + 1 : idx)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .gesture(DragGesture().onChanged { _ in lastAction = Date() })
            .onChange(of: pageState.pageIndex) { _, _ in lastAction = Date() }
            .onReceive(
                Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            ) { _ in
                guard Date().timeIntervalSince(lastAction) >= autoAdvanceAfter, pageCount > 1 else { return }
                withAnimation(.easeInOut) {
                    pageState.pageIndex = (pageState.pageIndex + 1) % pageCount
                }
            }
        }
    }
}

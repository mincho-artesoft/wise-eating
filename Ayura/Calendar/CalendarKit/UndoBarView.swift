//import SwiftUI
//
//struct UndoBarView: View {
//    let onUndo: () -> Void
//    var onCommit: () -> Void // Нов callback за финализиране
//    let itemsPendingCount: Int
//    
//    let timerDuration: TimeInterval = 10.0
//    @State private var timeRemaining: TimeInterval
//    @State private var internalTimer: Timer?
//
//    private let backgroundColor = Color.black.opacity(0.8)
//    private let foregroundColor = Color.white
//    private let progressColor = Color.white.opacity(0.5)
//
//    init(itemsPendingCount: Int, onUndo: @escaping () -> Void, onCommit: @escaping () -> Void) {
//        self.itemsPendingCount = itemsPendingCount
//        self.onUndo = onUndo
//        self.onCommit = onCommit
//        _timeRemaining = State(initialValue: timerDuration)
//    }
//
//    var body: some View {
//        ZStack(alignment: .leading) {
//            // Прогрес бар
//            GeometryReader { geometry in
//                Rectangle()
//                    .fill(progressColor)
//                    .frame(width: geometry.size.width * (CGFloat(timeRemaining / timerDuration)))
//                    .animation(.linear(duration: 0.1), value: timeRemaining)
//            }
//            
//            HStack {
//                Text("\(itemsPendingCount) item\(itemsPendingCount > 1 ? "s" : "") bought")
//                    .foregroundColor(foregroundColor)
//                    .font(.system(size: 13))
//                
//                Spacer()
//                
//                // Таймер в секунди
//                Text("\(Int(ceil(timeRemaining)))s")
//                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
//                    .foregroundColor(foregroundColor.opacity(0.8))
//                    .padding(.horizontal, 8)
//
//                Button(action: {
//                    self.stopTimer()
//                    self.onUndo()
//                }) {
//                    Text("Undo")
//                        .foregroundColor(foregroundColor)
//                        .font(.system(size: 13, weight: .bold))
//                }
//            }
//            .padding(.horizontal, 10)
//        }
//        .frame(height: 36)
//        .background(backgroundColor)
//        .cornerRadius(8)
//        .clipped()
//        .onAppear(perform: startTimer)
//        .onDisappear(perform: stopTimer)
//    }
//    
//    private func startTimer() {
//        stopTimer()
//        internalTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
//            DispatchQueue.main.async {
//                if self.timeRemaining > 0.05 {
//                    self.timeRemaining -= 0.1
//                } else {
//                    self.timeRemaining = 0
//                    self.stopTimer()
//                    self.onCommit() // Времето изтече, извикваме onCommit
//                }
//            }
//        }
//    }
//    
//    private func stopTimer() {
//        internalTimer?.invalidate()
//        internalTimer = nil
//    }
//}

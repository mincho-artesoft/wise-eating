import SwiftUI

struct MealRowsView: View {

    // MARK: – Inputs
    let rows: [(FoodItem, Double)]
    
    // --> ПРОМЯНА: Приема ObservableObject за управление на състоянието
    @ObservedObject var pageState: PageState

    // MARK: – State
    @State private var lastAction  = Date()
    private let autoAdvanceAfter: TimeInterval = 10

    // MARK: – Helpers
    private var pageCount: Int {
        rows.count > 1 ? rows.count + 1 : rows.count
    }

    // MARK: – Body
    var body: some View {
        GeometryReader { geo in
            // --> ПРОМЯНА: ZStack и точките са премахнати от тук
            
            //--------------------------------------------------------
            // TAB VIEW
            //--------------------------------------------------------
            TabView(selection: $pageState.pageIndex) {
                
                // 0) Summary
                if pageCount > 1 {
                    MealSummaryRowEventView(rows: rows)
                        .frame(maxWidth: geo.size.width, alignment: .leading)
                        .tag(0)
                }
                
                // 1…n) Храни
                ForEach(Array(rows.enumerated()), id: \.1.0.id) { idx, pair in
                    // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА 👇 -----
                    // Подаваме директно Double стойността (pair.1), без да я преобразуваме в Int.
                    FoodItemRowEventView(item: pair.0,
                                         amount: pair.1)
                    // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----
                        .frame(maxWidth: geo.size.width, alignment: .leading)
                        .tag(pageCount > 1 ? idx + 1 : idx)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .gesture(DragGesture().onChanged { _ in lastAction = Date() })
            .onChange(of: pageState.pageIndex) {lastAction = Date() }
            
            //------------------------------------------------------------
            // ТАЙМЕР ЗА АВТОСМЯНА
            //------------------------------------------------------------
            .onReceive(
                Timer.publish(every: 1, on: .main, in: .common)
                     .autoconnect()
            ) { _ in
                guard Date().timeIntervalSince(lastAction) >= autoAdvanceAfter,
                      pageCount > 1
                else { return }

                withAnimation(.easeInOut) {
                    pageState.pageIndex = (pageState.pageIndex + 1) % pageCount
                }
            }
        }
    }
}

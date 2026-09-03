import SwiftUI
import UIKit

/// SwiftUI мост към WeekCarouselView.
struct WeekCarouselRepresentable: UIViewRepresentable {
    
    @Binding var selectedDate: Date
    /// 0…1 или `nil`, ако няма данни.
    var progressProvider: (Date) -> Double?        // ⬅︎ Optional
    
    var onDaySelected: ((Date) -> Void)?
    
    func makeUIView(context: Context) -> WeekCarouselView {
        let v = WeekCarouselView()
        v.selectedDate         = selectedDate
        v.goalProgressProvider = progressProvider
        v.onDaySelected = { d in
            selectedDate = d
            onDaySelected?(d)
        }
        return v
    }
    func updateUIView(_ uiView: WeekCarouselView, context: Context) {
        // 1. винаги актуализираме данните
        uiView.selectedDate         = selectedDate
        uiView.goalProgressProvider = progressProvider

        // 2. пълно презареждане само ако сменяме деня;
        //    иначе – тиха подмяна на видимите клетки
        let dateChanged = !Calendar.current.isDate(uiView.selectedDate,
                                                   inSameDayAs: selectedDate)
        if dateChanged {
            uiView.reload()                              // вашият досегашен метод
        } else {
            uiView.reloadVisibleCellsWithoutAnimation()  // 🆕
        }
    }


}

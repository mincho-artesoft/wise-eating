import SwiftUI

// =====================================================================
// MARK: - Обвивката за SwiftUI: CalendarDateRangePickerWrapper
// =====================================================================
struct CalendarDateRangePickerWrapper: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    
    var startDate: Date?
    var endDate: Date?
    
    // По желание: минимална/максимална дата
    var minimumDate: Date?
    var maximumDate: Date?
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/3) +++
    /// Сет от дати, които трябва да имат индикатор (точка).
    var datesWithEvents: Set<Date>?
    // +++ КРАЙ НА ПРОМЯНАТА (1/3) +++
    
    // ПРОМЯНА: Премахваме selectedColor. Цветът вече се управлява автоматично от темата.
    // var selectedColor: UIColor? = nil
    
    // Callback при завършване
    var onComplete: ((Date, Date) -> Void)?

    func makeUIViewController(context: Context) -> UINavigationController {
        let pickerVC = CalendarDateRangePickerViewController()
        pickerVC.delegate = context.coordinator
        
        // Подаваме зададените стойности
        pickerVC.selectedStartDate = startDate
        pickerVC.selectedEndDate = endDate
        pickerVC.minimumDate = minimumDate
        pickerVC.maximumDate = maximumDate
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/3) +++
        pickerVC.datesWithEvents = datesWithEvents
        // +++ КРАЙ НА ПРОМЯНАТА (2/3) +++
        
        // ПРОМЯНА: Премахваме задаването на selectedColor.
        
        // 1) Създаваме UINavigationController
        let navController = UINavigationController(rootViewController: pickerVC)
        
        // 2) Презентация "над" текущия екран
        navController.modalPresentationStyle = .overFullScreen
        
        // 3) Правим фона му прозрачен (да не добавя тъмен слой)
        navController.view.backgroundColor = .clear
        
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Ако трябва да се обновява нещо динамично
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, @preconcurrency CalendarDateRangePickerViewControllerDelegate {
        var parent: CalendarDateRangePickerWrapper
        
        init(_ parent: CalendarDateRangePickerWrapper) {
            self.parent = parent
        }
        
        func didCancelPickingDateRange() {
            // Ако искате да се затваря при Cancel:
            // parent.presentationMode.wrappedValue.dismiss()
        }
        
        @MainActor func didPickDateRange(startDate: Date!, endDate: Date!) {
            if let s = startDate, let e = endDate {
                parent.onComplete?(s, e)
            }
            // Ако искате да се затваря след избор:
            // parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

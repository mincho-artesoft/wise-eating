import SwiftUI

struct CustomDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    var tintColor: UIColor
    var textColor: UIColor
    
    // --- ПРОМЯНА 1: Добавяме minimumDate и maximumDate ---
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil
    
    @ObservedObject private var effectManager = EffectManager.shared
    
    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.dateChanged),
            for: .valueChanged
        )
        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // --- ПРОМЯНА 2: Задаваме границите директно ---
        uiView.minimumDate = minimumDate
        uiView.maximumDate = maximumDate
        
        if uiView.date != selection {
            uiView.date = selection
        }
        
        uiView.overrideUserInterfaceStyle = effectManager.isLightRowTextColor ? .dark : .light
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CustomDatePicker

        init(_ parent: CustomDatePicker) {
            self.parent = parent
        }

        @MainActor @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}

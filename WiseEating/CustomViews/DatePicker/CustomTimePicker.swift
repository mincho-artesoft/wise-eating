import SwiftUI

struct CustomTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    var textColor: UIColor
    
    // --- ПРОМЯНА 1: Добавяме maximumDate ---
    var maximumDate: Date? = nil
    
    @ObservedObject private var effectManager = EffectManager.shared
    
    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .time
        datePicker.preferredDatePickerStyle = .compact
        datePicker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.timeChanged),
            for: .valueChanged
        )
        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // --- ПРОМЯНА 2: Задаваме максималната дата ---
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
        var parent: CustomTimePicker

        init(_ parent: CustomTimePicker) {
            self.parent = parent
        }

        @MainActor @objc func timeChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}

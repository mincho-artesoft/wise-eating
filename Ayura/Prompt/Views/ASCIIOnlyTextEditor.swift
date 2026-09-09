import SwiftUI
import UIKit

struct ASCIIOnlyTextEditor: UIViewRepresentable {
    @Binding var text: String
    var textColor: UIColor? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.keyboardType = .asciiCapable
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.isScrollEnabled = true
        if let c = textColor { tv.textColor = c }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if let c = textColor { uiView.textColor = c }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText repl: String) -> Bool {
            // Разреши триене
            if repl.isEmpty { return true }

            // Филтрирай към печатаеми ASCII + newline + tab
            let filteredScalars = repl.unicodeScalars.filter { s in
                (0x20...0x7E).contains(Int(s.value)) || s == "\n" || s == "\t"
            }
            let filtered = String(String.UnicodeScalarView(filteredScalars))

            if filtered == repl {
                return true // всичко е ОК
            } else {
                // Ръчно инжектираме филтрирания текст
                if let swiftRange = Range(range, in: textView.text) {
                    let newText = textView.text.replacingCharacters(in: swiftRange, with: filtered)
                    textView.text = newText
                    text.wrappedValue = newText
                }
                return false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

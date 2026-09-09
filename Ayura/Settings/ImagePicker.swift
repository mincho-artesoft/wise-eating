import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()

            guard let provider = results.first?.itemProvider else {
                return
            }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                // To avoid Sendable warnings, we must load a Sendable type like `Data` from the background thread.
                // Then, we can use that data to create the UIImage on the main thread.
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let error = error {
                        print("Error loading image data: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = data else {
                        return
                    }
                    
                    // Create the UIImage on the main thread
                    DispatchQueue.main.async {
                        self.parent.selectedImage = UIImage(data: data)
                    }
                }
            }
        }
    }
}

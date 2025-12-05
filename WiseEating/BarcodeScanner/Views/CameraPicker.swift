import SwiftUI
import AVFoundation

/// Основният View, който управлява логиката за достъп до камерата.
struct CameraPicker: View {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode
    
    // Следим статуса на правата
    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        Group {
            switch permissionStatus {
            case .authorized:
                // Ако имаме права, показваме контролера на камерата
                CameraPickerRepresentable(onImagePicked: onImagePicked)
                
            case .denied, .restricted:
                // Ако правата са отказани, показваме екрана за грешка
                PermissionDeniedView(
                    type: .camera,
                    hasBackground: true,
                    onTryAgain: {
                        checkPermission()
                    }
                )
                // Добавяме бутон за затваряне, защото PermissionDeniedView може да не го включва по подразбиране в този контекст
                .overlay(alignment: .topLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding()
                    .foregroundColor(.primary)
                }
                
            case .notDetermined:
                // Докато зареждаме или искаме права
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                }
                .task {
                    await requestPermission()
                }
                
            @unknown default:
                ContentUnavailableView("Unknown Camera Error", systemImage: "camera.badge.ellipsis")
            }
        }
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        // Обновяваме UI на главната нишка
        DispatchQueue.main.async {
            self.permissionStatus = status
        }
    }
    
    private func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        DispatchQueue.main.async {
            self.permissionStatus = granted ? .authorized : .denied
        }
    }
}

// MARK: - Internal Implementation
/// Това е оригиналният `CameraPicker`, сега преименуван и скрит, за да се ползва само вътрешно.
fileprivate struct CameraPickerRepresentable: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        // Задаваме черен фон, за да не се вижда бяло премигване при старт
        picker.view.backgroundColor = .black
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPickerRepresentable

        init(_ parent: CameraPickerRepresentable) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

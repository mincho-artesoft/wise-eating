import SwiftUI
import AVFoundation
import UIKit

/// Основният View, който управлява логиката за достъп до камерата в iOS.
struct CameraPicker: View {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var effectManager = EffectManager.shared

    // Следим статуса на правата
    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        Group {
            switch permissionStatus {
            case .authorized:
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
                .overlay(alignment: .topLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding()
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                
            case .notDetermined:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                }
                .task {
                    await requestPermission()
                }
                
            @unknown default:
                ContentUnavailableView("Unknown Camera Error", systemImage: "camera.badge.ellipsis")
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
        }
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
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

// MARK: - iOS Implementation
fileprivate struct CameraPickerRepresentable: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
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

import SwiftUI
import AVFoundation
import UIKit

/// Основният View, който управлява логиката за достъп до камерата.
/// Автоматично избира между Native UI за iOS и Custom AVFoundation UI за Mac Catalyst.
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
                // ⚠️ ТУК Е КЛЮЧОВАТА ПРОМЯНА ЗА MAC CATALYST
                #if targetEnvironment(macCatalyst)
                // На Mac използваме къстъм имплементация, защото UIImagePickerController крашва
                MacCameraView(onImagePicked: onImagePicked)
                #else
                // На iOS използваме стандартния контролер
                CameraPickerRepresentable(onImagePicked: onImagePicked)
                #endif
                
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
                    .foregroundColor(.primary)
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

// MARK: - 1. iOS Implementation (Standard)
#if !targetEnvironment(macCatalyst)
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
#else
// За да не гърми компилатора на Mac, слагаме празен стъб за iOS версията
fileprivate struct CameraPickerRepresentable: View {
    var onImagePicked: (UIImage) -> Void
    var body: some View { EmptyView() }
}
#endif

// MARK: - 2. Mac Catalyst Implementation (Custom AVFoundation)
#if targetEnvironment(macCatalyst)
fileprivate struct MacCameraView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> MacCameraViewController {
        let controller = MacCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MacCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MacCameraViewControllerDelegate {
        let parent: MacCameraView

        init(_ parent: MacCameraView) {
            self.parent = parent
        }

        func didCaptureImage(_ image: UIImage) {
            parent.onImagePicked(image)
            parent.presentationMode.wrappedValue.dismiss()
        }

        func didCancel() {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Протокол за комуникация
protocol MacCameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didCancel()
}

// Къстъм контролер за Mac камерата
final class MacCameraViewController: UIViewController {
    weak var delegate: MacCameraViewControllerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let queue = DispatchQueue(label: "camera-queue")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func setupCamera() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // 1. Input
            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                print("❌ MacCamera: Cannot add input")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoInput)
            
            // 2. Output
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
            
            // 3. Preview Layer (UI updates on main thread)
            DispatchQueue.main.async {
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                self.previewLayer.videoGravity = .resizeAspectFill
                self.previewLayer.frame = self.view.bounds
                self.view.layer.insertSublayer(self.previewLayer, at: 0)
            }
        }
    }
    
    private func setupUI() {
        // Capture Button
        let captureBtn = UIButton(type: .custom)
        captureBtn.backgroundColor = .white
        captureBtn.layer.cornerRadius = 35
        captureBtn.layer.borderWidth = 5
        captureBtn.layer.borderColor = UIColor.gray.cgColor
        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        captureBtn.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        
        // Cancel Button
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.backgroundColor = .black.withAlphaComponent(0.5)
        cancelBtn.layer.cornerRadius = 10
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        
        view.addSubview(captureBtn)
        view.addSubview(cancelBtn)
        
        NSLayoutConstraint.activate([
            captureBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),
            captureBtn.widthAnchor.constraint(equalToConstant: 70),
            captureBtn.heightAnchor.constraint(equalToConstant: 70),
            
            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),
            cancelBtn.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func cancel() {
        delegate?.didCancel()
    }
}

extension MacCameraViewController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        
        // Спираме сесията
        queue.async {
            self.captureSession.stopRunning()
        }
        
        DispatchQueue.main.async {
            self.delegate?.didCaptureImage(image)
        }
    }
}
#endif

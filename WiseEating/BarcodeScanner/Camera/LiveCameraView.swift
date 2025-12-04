import SwiftUI
import AVFoundation

public struct LiveCameraView: UIViewControllerRepresentable {
    public init(onResults: @escaping @Sendable ([DetectedObjectEntity]) -> Void) {
        self.onResults = onResults
    }
    let onResults: @Sendable ([DetectedObjectEntity]) -> Void

    public func makeUIViewController(context: Context) -> CameraController {
        let vc = CameraController()
        vc.onResults = onResults
        return vc
    }

    public func updateUIViewController(_ uiViewController: CameraController, context: Context) {}
}

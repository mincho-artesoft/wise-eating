import UIKit
import AVFoundation
import CoreMedia

/// Небезопасна, но практична кутия за предаване на non-Sendable обекти през граници на concurrency.
/// Използваме я САМО за read-only употреба (не модифицираме буфера).
final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

public final class CameraController: UIViewController,
                                     AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureMetadataOutputObjectsDelegate {

    // MARK: - Public API
    public var onResults: (([DetectedObjectEntity]) -> Void)?

    // MARK: - Private state
    private let session = AVCaptureSession()
    private let queue   = DispatchQueue(label: "camera.queue") // serial
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var isConfigured = false
    private var lastVisionRun = Date(timeIntervalSince1970: 0)

    private var videoOutput: AVCaptureVideoDataOutput?
    private var metadataOutput: AVCaptureMetadataOutput?

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        queue.async { [weak self] in
            guard let self = self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        queue.async { [weak self] in
            guard let self = self, self.isConfigured, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        applyCurrentOrientation()
    }

    // MARK: - Session setup
    private func setupSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        session.sessionPreset = .high
        
        // --- ПРОМЯНА: По-гъвкав избор на камера ---
        // 1. Опитваме задна камера (за iPhone/iPad)
        // 2. Опитваме предна камера (за Mac/iPhone Selfie)
        // 3. Опитваме каквато и да е видео камера (за външни уеб камери на Mac)
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        // Търсим приоритетно: Back -> Front -> Unspecified
        let devices = discoverySession.devices
        let device = devices.first(where: { $0.position == .back })
        ?? devices.first(where: { $0.position == .front })
        ?? devices.first
        
        guard let captureDevice = device else {
            NSLog("CameraController: No video device found.")
            return
        }
        // ------------------------------------------
        
        do {
            try captureDevice.lockForConfiguration()
            
            // Задаваме FPS само ако устройството го поддържа
            // (Някои стари уеб камери на Mac може да не поддържат фиксирано 15 FPS)
            let desiredFrameDuration = CMTimeMake(value: 1, timescale: 15)
            
            // Проверка за минимална продължителност
            if captureDevice.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
                range.minFrameDuration <= desiredFrameDuration && range.maxFrameDuration >= desiredFrameDuration
            }) {
                captureDevice.activeVideoMinFrameDuration = desiredFrameDuration
                captureDevice.activeVideoMaxFrameDuration = desiredFrameDuration
                NSLog("CameraController: Frame rate set to 15 FPS.")
            } else {
                NSLog("CameraController: 15 FPS not supported by hardware, using default.")
            }
            
            captureDevice.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            NSLog("CameraController: Failed to create input or configure device: \(error)")
            return
        }
        
        // Video output (Vision)
        let vOut = AVCaptureVideoDataOutput()
        vOut.alwaysDiscardsLateVideoFrames = true
        vOut.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(vOut) {
            session.addOutput(vOut)
            videoOutput = vOut
        }
        
        // Metadata (баркод/QR)
        let mOut = AVCaptureMetadataOutput()
        if session.canAddOutput(mOut) {
            session.addOutput(mOut)
            mOut.setMetadataObjectsDelegate(self, queue: queue)
            mOut.metadataObjectTypes = supportedMetadataTypes(for: mOut)
            metadataOutput = mOut
        }
        
        // Preview
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
        
        applyCurrentOrientation()
        isConfigured = !session.inputs.isEmpty && !session.outputs.isEmpty
    }

    private func supportedMetadataTypes(for output: AVCaptureMetadataOutput) -> [AVMetadataObject.ObjectType] {
        var types: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code128, .code39, .code93,
            .pdf417, .qr, .aztec, .dataMatrix, .itf14, .interleaved2of5
        ]
        types = types.filter { output.availableMetadataObjectTypes.contains($0) }
        return types
    }

    private func applyCurrentOrientation() {
            // iOS Логика
            let orientation = view.window?.windowScene?.interfaceOrientation
                ?? UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }.first
                ?? .portrait

            let videoOrientation: AVCaptureVideoOrientation
            switch orientation {
            case .portrait: videoOrientation = .portrait
            case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
            case .landscapeLeft: videoOrientation = .landscapeLeft
            case .landscapeRight: videoOrientation = .landscapeRight
            @unknown default: videoOrientation = .portrait
            }

            if let conn = previewLayer?.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = videoOrientation
            }
            if let vConn = videoOutput?.connection(with: .video), vConn.isVideoOrientationSupported {
                vConn.videoOrientation = videoOrientation
            }
        }
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public nonisolated func captureOutput(_ output: AVCaptureOutput,
                                          didOutput sampleBuffer: CMSampleBuffer,
                                          from connection: AVCaptureConnection) {
        // Rate-limit до 2 FPS за класификация
        let now = Date()
        guard now.timeIntervalSince(lastVisionRun) > 0.5 else { return }
        lastVisionRun = now

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Опаковаме non-Sendable буфера в unchecked кутия, за да не алармира Swift 6.
        let box = UncheckedSendableBox(pb)

        // Стартираме async задача (не detached), която работи на cooperative executor.
        Task { [weak self] in
            guard let self else { return }
            do {
                // Използваме опакования буфер
                let results = try await VisualExplainService.shared.classify(pixelBuffer: box.value)
                await DetectedObjectStore.shared.add(results)
                await MainActor.run { self.onResults?(results) }
            } catch {
                NSLog("Vision classify error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    public nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                           didOutput metadataObjects: [AVMetadataObject],
                                           from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        guard !codes.isEmpty else { return }

        let items = codes.map { code in
            let raw = code.stringValue ?? "—"
            let parsed = BarcodeParser.parse(raw)
            let sym = code.type.rawValue.uppercased()
            let kindPrefix = (code.type == .qr) ? "QR" : "Barcode"

            let explanation: String = {
                switch parsed.kind {
                case .url:
                    return "Opens: \(parsed.urlToOpen?.absoluteString ?? raw)"
                case .wifi:
                    let ssid = parsed.extras["ssid"] ?? "Unknown"
                    return "Wi-Fi network: \(ssid)"
                case .json:
                    return "JSON payload detected."
                case .gtin:
                    return "Product code (\(sym)): \(parsed.extras["gtin"] ?? raw)"
                case .gs1:
                    return "GS1: \(parsed.summary)"
                default:
                    return parsed.summary.isEmpty ? "Detected \(sym) barcode: \(raw)." : parsed.summary
                }
            }()

            return DetectedObjectEntity(
                id: UUID(),
                title: raw,
                category: "\(kindPrefix) · \(parsed.kind.rawValue)",
                confidence: 0.99,
                explanation: explanation,
                thumbnailKey: nil
            )
        }

        Task { @MainActor [weak self] in
            self?.onResults?(items)
        }
    }

}

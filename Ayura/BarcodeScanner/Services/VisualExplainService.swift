import Foundation
import Vision
import CoreVideo
import AppIntents
import UIKit
import CoreImage

public actor VisualExplainService {
    public static let shared = VisualExplainService()

    @inline(__always)
    private func vlog(_ msg: String) { print("🔎 [VisualExplainService] \(msg)") }

    // All supported symbologies in one place (adds ITF, GS1 DataBar family)
    private let supportedSymbologies: [VNBarcodeSymbology] = [
        .ean8, .ean13, .upce,
        .code128, .code39, .code93,
        .itf14, .i2of5, .i2of5Checksum,
        .qr, .pdf417, .aztec, .dataMatrix,
        .gs1DataBar, .gs1DataBarLimited, .gs1DataBarExpanded
    ]

    // MARK: Photos path (CGImage + EXIF orientation)
    public func classify(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [DetectedObjectEntity] {
        // Try barcodes first (as-provided orientation)
        if let codes = try? detectBarcodes(cgImage: cgImage, orientation: orientation), !codes.isEmpty {
            return codes
        }
        // Retry once with normalized .up (helps EXIF edge cases)
        if let normalized = await normalizeCGImage(cgImage, to: orientation),
           let codes = try? detectBarcodes(cgImage: normalized, orientation: .up),
           !codes.isEmpty {
            return codes
        }

        // As another fallback: CI-based contrast boost then detect
        if let pre = preprocessForBarcode(cgImage) {
            if let codes = try? detectBarcodes(cgImage: pre, orientation: .up), !codes.isEmpty {
                return codes
            }
        }

        // Generic classification
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try handler.perform([classify])

        var items: [DetectedObjectEntity] = []
        if let results = classify.results {
            for c in results.prefix(5) where c.confidence > 0.20 {
                let (title, cat) = Self.split(label: c.identifier)
                items.append(
                    DetectedObjectEntity(
                        id: UUID(),
                        title: title,
                        category: cat,
                        confidence: Double(c.confidence),
                        explanation: Self.explain(for: c.identifier, confidence: Double(c.confidence)),
                        thumbnailKey: nil
                    )
                )
            }
        }

        // Optional: Faces
        let faceReq = VNDetectFaceRectanglesRequest()
        try handler.perform([faceReq])
        if let faces = faceReq.results, !faces.isEmpty {
            let title = faces.count == 1 ? "Face" : "Faces"
            items.insert(
                DetectedObjectEntity(
                    id: UUID(),
                    title: title,
                    category: "Person",
                    confidence: 0.9,
                    explanation: faces.count == 1 ? "Detected a human face." : "Detected \(faces.count) human faces.",
                    thumbnailKey: nil
                ),
                at: 0
            )
        }

        return items
    }

    // MARK: Camera path (CVPixelBuffer)
    public func classify(pixelBuffer: CVPixelBuffer) async throws -> [DetectedObjectEntity] {
        if let codes = try? detectBarcodes(pixelBuffer: pixelBuffer, orientation: .up), !codes.isEmpty {
            return codes
        }

        // Generic classification
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([classify])

        var items: [DetectedObjectEntity] = []
        if let results = classify.results {
            for c in results.prefix(5) where c.confidence > 0.20 {
                let (title, cat) = Self.split(label: c.identifier)
                items.append(
                    DetectedObjectEntity(
                        id: UUID(),
                        title: title,
                        category: cat,
                        confidence: Double(c.confidence),
                        explanation: Self.explain(for: c.identifier, confidence: Double(c.confidence)),
                        thumbnailKey: nil
                    )
                )
            }
        }

        // Optional: Faces
        let faceReq = VNDetectFaceRectanglesRequest()
        try handler.perform([faceReq])
        if let faces = faceReq.results, !faces.isEmpty {
            let title = faces.count == 1 ? "Face" : "Faces"
            items.insert(
                DetectedObjectEntity(
                    id: UUID(),
                    title: title,
                    category: "Person",
                    confidence: 0.9,
                    explanation: faces.count == 1 ? "Detected a human face." : "Detected \(faces.count) human faces.",
                    thumbnailKey: nil
                ),
                at: 0
            )
        }

        return items
    }

    // Maps a Vision barcode observation to a richer DetectedObjectEntity using BarcodeParser.
    private func mapObservation(_ o: VNBarcodeObservation) -> DetectedObjectEntity {
        let raw = o.payloadStringValue ?? "—"
        let parsed = BarcodeParser.parse(raw)
        let sym = friendlySymbology(o.symbology)

        // If the payload is a URL, attempt GS1 Digital Link extraction (e.g., https://id.gs1.org/01/GTIN/...)
        if case .url = parsed.kind, let ais = extractGS1AIs(fromURLString: raw) {
            if let gtin = ais["01"] {
                let summaryParts: [String] = [
                    "GTIN \(gtin)",
                    ais["17"].map { "Expiry \($0)" },
                    ais["10"].map { "Lot \($0)" },
                    ais["21"].map { "Serial \($0)" },
                ].compactMap { $0 }
                let explanation = summaryParts.isEmpty ? "GS1 Digital Link" : summaryParts.joined(separator: " · ")

                return DetectedObjectEntity(
                    id: UUID(),
                    title: raw,
                    category: "QR · GS1 Digital Link",
                    confidence: Double(max(o.confidence, 0.99)),
                    explanation: explanation,
                    thumbnailKey: nil
                )
            }
        }

        let kindPrefix = (o.symbology == .qr) ? "QR" : "Barcode"
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
                return parsed.summary.isEmpty ? "Detected \(sym) barcode." : parsed.summary
            }
        }()

        return DetectedObjectEntity(
            id: UUID(),
            title: raw,
            category: "\(kindPrefix) · \(parsed.kind.rawValue)",
            confidence: Double(max(o.confidence, 0.99)),
            explanation: explanation,
            thumbnailKey: nil
        )
    }

    // Attempts to extract GS1 Application Identifiers from a GS1 Digital Link URL.
    private func extractGS1AIs(fromURLString s: String) -> [String:String]? {
        guard let url = URL(string: s) else { return nil }
        var ais: [String:String] = [:]

        // 1) Path-based AIs like /01/<gtin>/.../10/<lot>/21/<serial>
        let comps = url.path.split(separator: "/").map(String.init)
        var i = 0
        while i + 1 < comps.count {
            let key = comps[i]
            let val = comps[i+1]
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: key)) {
                ais[key] = val
                i += 2
                continue
            }
            i += 1
        }

        // 2) Query-based AIs: ?01=...&10=... or gtin=...
        if let qi = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in qi {
                let k = item.name.lowercased()
                if k == "01" || k == "10" || k == "17" || k == "21" {
                    if let v = item.value { ais[k] = v }
                } else if k == "gtin", let v = item.value { ais["01"] = v }
            }
        }

        return ais.isEmpty ? nil : ais
    }

    // MARK: - New barcode helpers (no CPU-only; broaden symbologies)
    private func detectBarcodes(cgImage: CGImage, orientation: CGImagePropertyOrientation) throws -> [DetectedObjectEntity] {
        // 1) Try GPU-accelerated path first
        do {
            let req = VNDetectBarcodesRequest()
            req.preferBackgroundProcessing = true
            req.symbologies = supportedSymbologies
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([req])
            if let obs = req.results, !obs.isEmpty {
                vlog("Found \(obs.count) barcode(s) [cgImage/GPU].")
                return obs.map { mapObservation($0) }
            }
        } catch { /* silence */ }

        // 2) CPU-only retry on the same CGImage
        do {
            let reqCPU = VNDetectBarcodesRequest()
            reqCPU.symbologies = supportedSymbologies
            let handlerCPU = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handlerCPU.perform([reqCPU])
            if let obs = reqCPU.results, !obs.isEmpty {
                vlog("Found \(obs.count) barcode(s) [cgImage/CPU].")
                return obs.map { mapObservation($0) }
            }
        } catch { /* silence */ }

        // 2b) CPU retry across older revisions on original image
        do {
            let supported = Array(VNDetectBarcodesRequest.supportedRevisions).sorted()
            for rev in supported {
                let reqRev = VNDetectBarcodesRequest()
                reqRev.revision = rev
                reqRev.symbologies = supportedSymbologies
                let handlerRev = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handlerRev.perform([reqRev])
                    if let obs = reqRev.results, !obs.isEmpty {
                        vlog("Found \(obs.count) barcode(s) [cgImage/CPU rev=\(rev)].")
                        return obs.map { mapObservation($0) }
                    }
                } catch { /* silence */ }
            }
        }

        // 3) Sanitize: ensure 8-bit sRGB BGRA and optionally downscale, then retry
        if let sanitized = sanitizeCGImage(cgImage) {
            // 3a) GPU attempt on sanitized
            do {
                let req = VNDetectBarcodesRequest()
                req.preferBackgroundProcessing = true
                req.symbologies = supportedSymbologies
                let handler = VNImageRequestHandler(cgImage: sanitized, orientation: .up)
                try handler.perform([req])
                if let obs = req.results, !obs.isEmpty {
                    vlog("Found \(obs.count) barcode(s) [sanitized/GPU].")
                    return obs.map { mapObservation($0) }
                }
            } catch { /* silence */ }

            // 3b) CPU attempt on sanitized
            do {
                let reqCPU = VNDetectBarcodesRequest()
                reqCPU.symbologies = supportedSymbologies
                let handlerCPU = VNImageRequestHandler(cgImage: sanitized, orientation: .up)
                try handlerCPU.perform([reqCPU])
                if let obs = reqCPU.results, !obs.isEmpty {
                    vlog("Found \(obs.count) barcode(s) [sanitized/CPU].")
                    return obs.map { mapObservation($0) }
                }
            } catch { /* silence */ }

            // 3c) CPU retry across older revisions on sanitized image
            do {
                let supported = Array(VNDetectBarcodesRequest.supportedRevisions).sorted()
                for rev in supported {
                    let reqRev = VNDetectBarcodesRequest()
                    reqRev.revision = rev
                    reqRev.symbologies = supportedSymbologies
                    let handlerRev = VNImageRequestHandler(cgImage: sanitized, orientation: .up)
                    do {
                        try handlerRev.perform([reqRev])
                        if let obs = reqRev.results, !obs.isEmpty {
                            vlog("Found \(obs.count) barcode(s) [sanitized/CPU rev=\(rev)].")
                            return obs.map { mapObservation($0) }
                        }
                    } catch { /* silence */ }
                }
            }
        }

        return []
    }

    // Increase contrast and convert to sRGB BGRA CGImage (helps weak prints & PNGs)
    private func preprocessForBarcode(_ cg: CGImage, contrast: CGFloat = 1.25, maxLongSide: Int = 2048) -> CGImage? {
        let input = CIImage(cgImage: cg)

        // Desaturate + boost contrast
        guard let colorControls = CIFilter(name: "CIColorControls") else { return nil }
        colorControls.setValue(input, forKey: kCIInputImageKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
        colorControls.setValue(contrast, forKey: kCIInputContrastKey)
        let output = colorControls.outputImage ?? input

        // Optional downscale for huge images
        let extent = output.extent
        let longSide = max(extent.width, extent.height)
        let scale = longSide > CGFloat(maxLongSide) ? CGFloat(maxLongSide)/longSide : 1
        let finalImage: CIImage
        if scale < 1, let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(output, forKey: kCIInputImageKey)
            lanczos.setValue(scale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            finalImage = lanczos.outputImage ?? output
        } else {
            finalImage = output
        }

        let ctxGPU = CIContext(options: nil)
        if let cgOut = ctxGPU.createCGImage(finalImage, from: finalImage.extent) { return cgOut }
        let ctxCPU = CIContext(options: [CIContextOption.useSoftwareRenderer: true])
        return ctxCPU.createCGImage(finalImage, from: finalImage.extent)
    }

    // Convert a CVPixelBuffer to CGImage (GPU first, then CPU fallback)
    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Try GPU/Metal-backed context first
        let ctxGPU = CIContext(options: nil)
        if let cg = ctxGPU.createCGImage(ciImage, from: ciImage.extent) {
            return cg
        }
        // Fallback to software renderer (slower but robust)
        let ctxCPU = CIContext(options: [CIContextOption.useSoftwareRenderer: true])
        return ctxCPU.createCGImage(ciImage, from: ciImage.extent)
    }

    private func detectBarcodes(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [DetectedObjectEntity] {
        // Try GPU-accelerated path first
        do {
            let req = VNDetectBarcodesRequest()
            req.preferBackgroundProcessing = true
            req.symbologies = supportedSymbologies
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
            try handler.perform([req])
            if let obs = req.results, !obs.isEmpty {
                vlog("Found \(obs.count) barcode(s) [pixelBuffer/GPU].")
                return obs.map { mapObservation($0) }
            }
        } catch { /* silence */ }

        // Retry with CPU-only on the original pixel buffer
        do {
            let reqCPU = VNDetectBarcodesRequest()
            reqCPU.symbologies = supportedSymbologies
            let handlerCPU = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
            try handlerCPU.perform([reqCPU])
            if let obs = reqCPU.results, !obs.isEmpty {
                vlog("Found \(obs.count) barcode(s) [pixelBuffer/CPU].")
                return obs.map { mapObservation($0) }
            }
        } catch { /* silence */ }

        // CPU retry across older Vision revisions (some devices/sims need this)
        do {
            let supported = Array(VNDetectBarcodesRequest.supportedRevisions).sorted()
            for rev in supported {
                let reqRev = VNDetectBarcodesRequest()
                reqRev.revision = rev
                reqRev.symbologies = supportedSymbologies
                let handlerRev = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
                do {
                    try handlerRev.perform([reqRev])
                    if let obs = reqRev.results, !obs.isEmpty {
                        vlog("Found \(obs.count) barcode(s) [pixelBuffer/CPU rev=\(rev)].")
                        return obs.map { mapObservation($0) }
                    }
                } catch { /* silence */ }
            }
        }

        // Final fallback: convert pixel buffer to CGImage and reuse CGImage path
        if let cg = cgImage(from: pixelBuffer) {
            if let codes = try? detectBarcodes(cgImage: cg, orientation: orientation), !codes.isEmpty {
                vlog("Found \(codes.count) barcode(s) [pixelBuffer→CGImage fallback].")
                return codes
            }
        }

        return []
    }

    // Ensure 8-bit sRGB BGRA and optionally downscale very large images to a reasonable size
    private func sanitizeCGImage(_ cg: CGImage, maxLongSide: Int = 2048) -> CGImage? {
        let width = cg.width
        let height = cg.height
        let longSide = max(width, height)
        let scale: CGFloat = longSide > maxLongSide ? CGFloat(maxLongSide) / CGFloat(longSide) : 1
        let dstW = max(1, Int((CGFloat(width) * scale).rounded()))
        let dstH = max(1, Int((CGFloat(height) * scale).rounded()))

        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        return ctx.makeImage()
    }

    // Normalize a CGImage to .up orientation (one-time draw)
    private func normalizeCGImage(_ cg: CGImage, to orientation: CGImagePropertyOrientation) async -> CGImage? {
        await MainActor.run {
            let ui = UIImage(cgImage: cg, scale: 1, orientation: UIImage.Orientation(orientation))
            let size = ui.size
            UIGraphicsBeginImageContextWithOptions(size, false, ui.scale)
            defer { UIGraphicsEndImageContext() }
            ui.draw(in: CGRect(origin: .zero, size: size))
            return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
        }
    }

    // MARK: Helpers
    private func friendlySymbology(_ s: VNBarcodeSymbology) -> String {
        switch s {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .itf14: return "ITF-14"
        case .qr: return "QR"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        default: return s.rawValue
        }
    }

    private static func split(label: String) -> (String, String?) {
        if let slash = label.firstIndex(of: "/") {
            let cat = String(label[..<slash])
            let title = String(label[label.index(after: slash)...])
            return (title.capitalized, cat.capitalized)
        }
        return (label.capitalized, nil)
    }

    private static func explain(for identifier: String, confidence: Double) -> String {
        let key = identifier.lowercased()
        switch key {
        case let s where s.contains("cat"): return "Likely a domestic cat."
        case let s where s.contains("dog"): return "Likely a dog breed."
        case let s where s.contains("car") || s.contains("automobile"): return "An automobile, possibly a sedan or SUV."
        case let s where s.contains("bicycle"): return "A bicycle. Two wheels, human-powered."
        case let s where s.contains("pizza"): return "A pizza; round flatbread with toppings."
        default: return "Detected \(identifier) with \(Int(confidence * 100))% confidence."
        }
    }
}


// MARK: - Receipt OCR (extract line items)
public struct ReceiptItem: Sendable, Hashable { public let name: String; public let price: Double? }

public func ocrReceipt(cgImage: CGImage) async throws -> [ReceiptItem] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US", "en-GB"]
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    try handler.perform([request])
    guard let observations = request.results, !observations.isEmpty else { return [] }

    var items: [ReceiptItem] = []
    let priceRegex = try NSRegularExpression(pattern: #"([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)\.[0-9]{2}$"#, options: [])
    for obs in observations {
        let line = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !line.isEmpty else { continue }
        let lower = line.lowercased()
        if lower.contains("subtotal") || lower.contains("total") || lower.contains("tax") || lower.contains("change due") { continue }
        let fullRange = NSRange(location: 0, length: (line as NSString).length)
        if let match = priceRegex.firstMatch(in: line, options: [], range: fullRange) {
            let priceStr = (line as NSString).substring(with: match.range)
            let normalized = priceStr.replacingOccurrences(of: ",", with: "")
            let price = Double(normalized)
            let name = line.replacingOccurrences(of: priceStr, with: "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { items.append(.init(name: name, price: price)) }
        } else if line.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            items.append(.init(name: line, price: nil))
        }
    }
    return items
}

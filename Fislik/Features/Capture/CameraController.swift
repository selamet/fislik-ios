@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import UIKit
import Vision

/// Normalized receipt quad (Vision coordinates: origin bottom-left, 0…1).
struct Quad: Equatable {
    var topLeft, topRight, bottomRight, bottomLeft: CGPoint

    init(_ o: VNRectangleObservation) {
        topLeft = o.topLeft
        topRight = o.topRight
        bottomRight = o.bottomRight
        bottomLeft = o.bottomLeft
    }

    func distance(to other: Quad) -> CGFloat {
        let pairs = [(topLeft, other.topLeft), (topRight, other.topRight), (bottomRight, other.bottomRight), (bottomLeft, other.bottomLeft)]
        return pairs.map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }.max() ?? 1
    }
}

/// Camera session with live rectangle detection, stability-based auto capture and perspective correction.
@MainActor
@Observable
final class CameraController: NSObject {
    enum Authorization { case unknown, authorized, denied }

    private(set) var authorization: Authorization = .unknown
    private(set) var quad: Quad?
    private(set) var stable = false
    private(set) var capturing = false
    var torchOn = false { didSet { applyTorch() } }
    var autoCapture = true
    var onCapture: ((UIImage) -> Void)?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.selamet.fislik.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var stableSince: Date?
    @ObservationIgnored private var lastCapture = Date.distantPast
    @ObservationIgnored private nonisolated(unsafe) var lastAnalysis = Date.distantPast

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorization = .authorized
        case .notDetermined:
            authorization = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        default: authorization = .denied
        }
        guard authorization == .authorized else { return }
        configure()
        let session = session
        queue.async { session.startRunning() }
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
        torchOn = false
    }

    private func configure() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        self.device = device
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        device.unlockForConfiguration()
        session.commitConfiguration()
    }

    private func applyTorch() {
        guard let device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }

    func capture() {
        guard !capturing, authorization == .authorized else { return }
        capturing = true
        lastCapture = Date()
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .balanced
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    fileprivate func update(with observation: VNRectangleObservation?) {
        guard let observation else {
            quad = nil
            stable = false
            stableSince = nil
            return
        }
        let new = Quad(observation)
        if let old = quad, old.distance(to: new) < 0.025 {
            if stableSince == nil { stableSince = Date() }
        } else {
            stableSince = nil
        }
        quad = new
        stable = stableSince.map { Date().timeIntervalSince($0) > 0.35 } ?? false
        if autoCapture, let since = stableSince, Date().timeIntervalSince(since) > 1.0, Date().timeIntervalSince(lastCapture) > 2.0 {
            stableSince = nil
            capture()
        }
    }

    fileprivate func finish(with data: Data?) {
        defer { capturing = false }
        guard let data, let image = UIImage(data: data) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCapture?(Self.cropToReceipt(image) ?? image)
    }

    /// Re-detects the receipt on the full-resolution photo and applies perspective correction.
    nonisolated static func cropToReceipt(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1
        request.minimumSize = 0.25
        request.quadratureTolerance = 25
        request.minimumConfidence = 0.6
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
        guard let r = request.results?.first else { return nil }

        let ci = CIImage(cgImage: cg).oriented(orientation)
        let size = ci.extent.size
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ci
        filter.topLeft = point(r.topLeft)
        filter.topRight = point(r.topRight)
        filter.bottomLeft = point(r.bottomLeft)
        filter.bottomRight = point(r.bottomRight)
        guard let output = filter.outputImage, let result = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: result)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastAnalysis) > 0.12, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = Date()
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1
        request.minimumSize = 0.3
        request.quadratureTolerance = 25
        request.minimumConfidence = 0.7
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let observation = request.results?.first
        Task { @MainActor in self.update(with: observation) }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in self.finish(with: data) }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

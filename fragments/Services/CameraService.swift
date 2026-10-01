//
//  CameraService.swift
//  fragments
//
//  Created on 9/14/26.
//

import SwiftUI
import AVFoundation

// MARK: - Camera Service (AVFoundation Controller)

@Observable
public final class CameraService: NSObject, @unchecked Sendable {
    // MARK: - Published Properties

    public var isSessionRunning: Bool = false
    public var isAuthorized: Bool = false
    public var isFrontCamera: Bool = false
    public var currentZoomFactor: CGFloat = 1.0
    public var isTorchOn: Bool = false
    public var isRecordingVideo: Bool = false
    public var isUnavailable: Bool = false

    // MARK: - AVFoundation Objects

    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.fragments.camera.sessionQueue")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    // Handlers
    private var photoCaptureCompletion: ((UIImage?, URL?) -> Void)?
    private var videoRecordingCompletion: ((URL?, TimeInterval) -> Void)?
    private var recordingStartTime: Date?

    // MARK: - Video / Audio Configuration

    public var isForVideo: Bool = false

    // MARK: - Singleton / Instance

    public init(isForVideo: Bool = false) {
        self.isForVideo = isForVideo
        super.init()
        // NOTE: no permission request here. `AVCaptureDevice.requestAccess`
        // fires a system prompt, so it must only run after an explicit user
        // interaction — `prepare()` when the capture UI actually appears.
        // Never request from init.
    }

    /// Explicit point-of-use entry point, called when the capture UI appears.
    /// Safe to call repeatedly; only prompts when status is `.notDetermined`.
    public func prepare() {
        checkPermissions()
        if isForVideo {
            checkMicrophonePermission()
        }
    }

    // MARK: - Permissions

    /// Microphone is only needed for video sound. Requested just-in-time when
    /// the video capture UI appears — voice memos request separately in
    /// `AudioRecorderManager.startRecording()`.
    public func checkMicrophonePermission() {
        #if targetEnvironment(simulator)
        #else
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        #endif
    }

    public func checkPermissions() {
        #if targetEnvironment(simulator)
        self.isAuthorized = true
        self.isUnavailable = true
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        case .denied, .restricted:
            self.isAuthorized = false
        @unknown default:
            self.isAuthorized = false
        }
        #endif
    }

    // MARK: - Session Setup

    public func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            // 1. Video Input
            let deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
            guard let videoDevice = AVCaptureDevice.default(deviceType, for: .video, position: .back) else {
                DispatchQueue.main.async {
                    self.isUnavailable = true
                }
                self.captureSession.commitConfiguration()
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                    self.videoDeviceInput = videoInput
                }

                // 2. Audio Input (ONLY for video recording, never lock audio for photo camera)
                if self.isForVideo, let audioDevice = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.captureSession.canAddInput(audioInput) {
                        self.captureSession.addInput(audioInput)
                        self.audioDeviceInput = audioInput
                    }
                }

                // 3. Photo Output
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.maxPhotoQualityPrioritization = .balanced
                }

                // 4. Movie Output (capped at 5 seconds maximum)
                if self.captureSession.canAddOutput(self.movieOutput) {
                    self.captureSession.addOutput(self.movieOutput)
                    self.movieOutput.maxRecordedDuration = CMTime(seconds: 5.0, preferredTimescale: 600)
                }

                self.captureSession.commitConfiguration()
            } catch {
                DispatchQueue.main.async {
                    self.isUnavailable = true
                }
                self.captureSession.commitConfiguration()
            }
        }
    }

    // MARK: - Start / Stop Session

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
            }
        }
    }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Zoom Control (1x / 2x)

    public func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let targetZoom = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = targetZoom
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentZoomFactor = targetZoom
                }
            } catch {
                print("Failed to set zoom: \(error)")
            }
        }
    }

    // MARK: - Camera Flip (Front / Back)

    public func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let currentPosition = self.videoDeviceInput?.device.position ?? .back
            let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.captureSession.beginConfiguration()
                if let oldInput = self.videoDeviceInput {
                    self.captureSession.removeInput(oldInput)
                }

                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.videoDeviceInput = newInput
                } else if let oldInput = self.videoDeviceInput {
                    self.captureSession.addInput(oldInput)
                }

                self.captureSession.commitConfiguration()

                DispatchQueue.main.async {
                    self.isFrontCamera = (newPosition == .front)
                    self.currentZoomFactor = 1.0
                }
            } catch {
                print("Failed to flip camera: \(error)")
            }
        }
    }

    // MARK: - Torch / Flashlight Control

    public func setTorch(on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isTorchOn = on
                }
            } catch {
                print("Failed to set torch: \(error)")
            }
        }
    }

    // MARK: - Tap to Focus & Exposure

    public func focus(at point: CGPoint, in previewRect: CGRect) {
        let x = point.y / previewRect.height
        let y = 1.0 - (point.x / previewRect.width)
        let focusPoint = CGPoint(x: x, y: y)

        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                print("Failed to focus: \(error)")
            }
        }
    }

    // MARK: - Photo Capture

    public func capturePhoto(isFlashOn: Bool, completion: @escaping (UIImage?, URL?) -> Void) {
        // TEMPORARY trace (no behavior change).
        print("[PhotoTrace] CAMERA_CAPTURE_START")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.photoCaptureCompletion = completion

            #if targetEnvironment(simulator)
            let isSim = true
            #else
            let isSim = self.isUnavailable || self.videoDeviceInput == nil
            #endif

            if isSim {
                let size = CGSize(width: 1080, height: 1440)
                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { ctx in
                    let colors = [
                        UIColor(red: 0.95, green: 0.55, blue: 0.35, alpha: 1.0).cgColor,
                        UIColor(red: 0.85, green: 0.25, blue: 0.65, alpha: 1.0).cgColor,
                        UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1.0).cgColor
                    ]
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.5, 1.0])!
                    ctx.cgContext.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: size.width, y: size.height), options: [])

                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 52, weight: .bold),
                        .foregroundColor: UIColor.white
                    ]
                    let text = "✨ Captured Fragment"
                    let textSize = text.size(withAttributes: titleAttrs)
                    let textRect = CGRect(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 - 40, width: textSize.width, height: textSize.height)
                    text.draw(in: textRect, withAttributes: titleAttrs)

                    let subAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.8)
                    ]
                    let subText = Date().formatted(date: .abbreviated, time: .standard)
                    let subSize = subText.size(withAttributes: subAttrs)
                    let subRect = CGRect(x: (size.width - subSize.width) / 2, y: textRect.maxY + 16, width: subSize.width, height: subSize.height)
                    subText.draw(in: subRect, withAttributes: subAttrs)
                }

                let filename = "IMG_\(UUID().uuidString).jpg"
                let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: fileURL)
                }

                // TEMPORARY trace (no behavior change).
                print("[PhotoTrace] CAMERA_CAPTURE_COMPLETION simulator")
                print("[PhotoTrace] capturedFileURL: \(fileURL.path)")
                print("[PhotoTrace] fileExists: \(FileManager.default.fileExists(atPath: fileURL.path))")
                print("[PhotoTrace] fileSize: \((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? -1)")

                DispatchQueue.main.async {
                    completion(image, fileURL)
                }
                return
            }

            let settings = AVCapturePhotoSettings()
            if self.videoDeviceInput?.device.hasFlash == true {
                settings.flashMode = isFlashOn ? .on : .off
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Video Recording

    public func configureForVideo() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = self.isFrontCamera
                }
            }
            self.captureSession.commitConfiguration()
        }
    }

    public func configureForPhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .high
            }
            self.captureSession.commitConfiguration()
        }
    }

    public func startVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.movieOutput.isRecording else { return }

            #if targetEnvironment(simulator)
            self.recordingStartTime = Date()
            DispatchQueue.main.async {
                self.isRecordingVideo = true
            }
            return
            #else
            if self.isUnavailable || self.videoDeviceInput == nil {
                self.recordingStartTime = Date()
                DispatchQueue.main.async {
                    self.isRecordingVideo = true
                }
                return
            }
            #endif

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            self.recordingStartTime = Date()
            self.movieOutput.maxRecordedDuration = CMTime(seconds: 5.0, preferredTimescale: 600)

            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = self.isFrontCamera
                }
            }

            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecordingVideo = true
            }
        }
    }

    public func stopVideoRecording(completion: @escaping (URL?, TimeInterval) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            #if targetEnvironment(simulator)
            let duration = self.recordingStartTime != nil ? Date().timeIntervalSince(self.recordingStartTime!) : 2.5
            self.recordingStartTime = nil
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try? Data().write(to: tempURL)
            DispatchQueue.main.async {
                self.isRecordingVideo = false
                completion(tempURL, duration)
            }
            return
            #else
            if self.isUnavailable || self.videoDeviceInput == nil {
                let duration = self.recordingStartTime != nil ? Date().timeIntervalSince(self.recordingStartTime!) : 2.5
                self.recordingStartTime = nil
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                try? Data().write(to: tempURL)
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    completion(tempURL, duration)
                }
                return
            }
            #endif

            guard self.movieOutput.isRecording else { return }
            self.videoRecordingCompletion = completion
            self.movieOutput.stopRecording()

            DispatchQueue.main.async {
                self.isRecordingVideo = false
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            // TEMPORARY trace (no behavior change).
            print("[PhotoTrace] CAMERA_CAPTURE_COMPLETION device-failure error: \(error?.localizedDescription ?? "nil")")
            DispatchQueue.main.async {
                self.photoCaptureCompletion?(nil, nil)
            }
            return
        }

        // Save image to app temporary / documents directory
        let filename = "IMG_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        try? data.write(to: fileURL)

        // TEMPORARY trace (no behavior change).
        print("[PhotoTrace] CAMERA_CAPTURE_COMPLETION device")
        print("[PhotoTrace] capturedFileURL: \(fileURL.path)")
        print("[PhotoTrace] fileExists: \(FileManager.default.fileExists(atPath: fileURL.path))")
        print("[PhotoTrace] fileSize: \((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? -1)")

        DispatchQueue.main.async {
            self.photoCaptureCompletion?(image, fileURL)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let duration: TimeInterval
        if let start = recordingStartTime {
            duration = Date().timeIntervalSince(start)
        } else {
            duration = 0
        }

        DispatchQueue.main.async {
            self.videoRecordingCompletion?(outputFileURL, duration)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.updateOrientation()
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
        uiView.updateOrientation()
    }
}

public final class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private var startObserver: NSObjectProtocol?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        videoPreviewLayer.videoGravity = .resizeAspectFill
        startObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOrientation()
        }
    }

    deinit {
        if let observer = startObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func updateOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 && bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoPreviewLayer.frame = bounds
        videoPreviewLayer.videoGravity = .resizeAspectFill
        updateOrientation()
        CATransaction.commit()
    }
}

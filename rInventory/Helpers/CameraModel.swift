//
//  CameraModel.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/25/25.
//
// Camera model to handle camera functionality

import SwiftUI
import AVFoundation
import Combine

class CameraModel: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var selectedImage: UIImage?
    
    // Add focus and exposure points
    @Published var focusPoint: CGPoint?
    @Published var exposureValue: Float = 0.0
    @Published var showExposureSlider: Bool = false
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoCaptureDevice: AVCaptureDevice?
    private var completionHandler: ((UIImage?) -> Void)?
    
    // Camera capabilities
    var hasFlash: Bool = false
    var hasOtherCameras: Bool = false
    var maxTelephotoZoom: Int = 2
    var isFrontCameraActive: Bool = false
    
    // Camera devices
    var backUltraWideCamera: AVCaptureDevice?
    var backWideCamera: AVCaptureDevice?
    var backTelephotoCamera: AVCaptureDevice?
    var frontUltraWideCamera: AVCaptureDevice?
    var frontWideCamera: AVCaptureDevice?
    
    // Zoom ranges for smooth transitions
    private let ultraWideZoomRange: ClosedRange<CGFloat> = 0.5...0.9
    private let wideZoomRange: ClosedRange<CGFloat> = 1.0...1.9
    private let telephotoZoomRange: ClosedRange<CGFloat> = 2.0...10.0
    
    // Available lenses
    var availableLenses: [CameraLens] = []
    
    // Store camera devices in a dictionary for easy access
    private var cameraDevices: [AVCaptureDevice.Position: AVCaptureDevice] = [:]
    
    override init() {
        super.init()
        checkCameraCapabilities()
    }
    
    func requestAndCheckPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            permissionGranted = false
        }
    }
    
    private func checkCameraCapabilities() {
        // Check back camera capabilities
        let backDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        
        // Check front camera capabilities
        let frontDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        
        let hasBackCamera = !backDiscovery.devices.isEmpty
        let hasFrontCamera = !frontDiscovery.devices.isEmpty
        hasOtherCameras = hasBackCamera && hasFrontCamera
        
        // Check for cameras
        for device in backDiscovery.devices {
            if device.hasFlash {
                hasFlash = true
            }
            
            if device.deviceType == .builtInUltraWideCamera {
                backUltraWideCamera = device
            } else if device.deviceType == .builtInWideAngleCamera {
                backWideCamera = device
                cameraDevices[.back] = device // Default back camera to wide
            } else if device.deviceType == .builtInTelephotoCamera {
                backTelephotoCamera = device
                // Determine max telephoto zoom based on device capabilities
                maxTelephotoZoom = max(maxTelephotoZoom, Int(device.activeFormat.videoMaxZoomFactor))
            }
        }
        
        for device in frontDiscovery.devices {
            if device.deviceType == .builtInUltraWideCamera {
                frontUltraWideCamera = device
            } else if device.deviceType == .builtInWideAngleCamera {
                frontWideCamera = device
                cameraDevices[.front] = device // Default front camera to wide
            }
        }
        
        // Populate available lenses for both front and back cameras
        updateAvailableLenses()
    }
    
    private func updateAvailableLenses() {
        availableLenses.removeAll()
        
        if isFrontCameraActive {
            // Front camera lenses
            if frontUltraWideCamera != nil {
                availableLenses.append(CameraLens(
                    name: "0.5×",
                    zoomFactor: 0.5,
                    iconName: "arrow.up.left.and.arrow.down.right"
                ))
            }
            availableLenses.append(CameraLens(
                name: "1×",
                zoomFactor: 1.0,
                iconName: frontUltraWideCamera != nil ? "arrow.down.right.and.arrow.up.left" : nil
            ))
        } else {
            // Back camera lenses
            if backUltraWideCamera != nil {
                availableLenses.append(CameraLens(
                    name: "0.5×",
                    zoomFactor: 0.5,
                    iconName: ""
                ))
            }
            availableLenses.append(CameraLens(
                name: "1×",
                zoomFactor: 1.0,
                iconName: backUltraWideCamera != nil ? "" : nil
            ))
            if backTelephotoCamera != nil {
                availableLenses.append(CameraLens(
                    name: "\(maxTelephotoZoom)×",
                    zoomFactor: CGFloat(maxTelephotoZoom),
                    iconName: ""
                ))
            } else {
                // Add digital 2x option if no telephoto lens available
                availableLenses.append(CameraLens(
                    name: "2×",
                    zoomFactor: 2.0,
                    iconName: ""
                ))
            }
        }
    }
    
    private func setupCamera() {
        session.sessionPreset = .photo
        
        guard let videoCaptureDevice = cameraDevices[.back],
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            return
        }
        
        self.videoCaptureDevice = videoCaptureDevice
        self.isFrontCameraActive = false
        
        if session.canAddInput(videoInput) && session.canAddOutput(photoOutput) {
            session.addInput(videoInput)
            session.addOutput(photoOutput)
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }
    
    func switchCamera() {
        session.beginConfiguration()
        
        // Remove existing inputs
        session.inputs.forEach { session.removeInput($0) }
        
        let currentPosition = videoCaptureDevice?.position ?? .back
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        
        // Get the appropriate camera device
        var newCamera: AVCaptureDevice?
        
        if newPosition == .front {
            // Default to wide when switching to front
            newCamera = cameraDevices[.front]
        } else {
            // Default to wide when switching to back
            newCamera = cameraDevices[.back]
        }
        
        guard let camera = newCamera,
              let newInput = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }
        
        videoCaptureDevice = camera
        isFrontCameraActive = newPosition == .front
        
        if session.canAddInput(newInput) {
            session.addInput(newInput)
        }
        
        session.commitConfiguration()
        
        // Update available lenses for the new camera position
        updateAvailableLenses()
        
        // Clear the focus point when switching cameras
        DispatchQueue.main.async {
            self.focusPoint = nil
            self.showExposureSlider = false
            self.objectWillChange.send()
        }
    }
    
    func zoom(with factor: CGFloat) {
        guard let device = videoCaptureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Calculate appropriate zoom factor based on device capabilities
            let maxZoom = device.activeFormat.videoMaxZoomFactor
            let minZoom = device.minAvailableVideoZoomFactor
            
            // Clamp the zoom factor within the device's capabilities
            let zoomFactor = max(minZoom, min(factor, maxZoom))
            
            // Apply the zoom
            device.videoZoomFactor = zoomFactor
            
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error.localizedDescription)")
        }
    }
    
    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        self.flashMode = mode
        // Note: The actual flash will be applied when taking the photo via photoOutput settings
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.completionHandler = completion
        
        // Configure photo settings
        let settings = AVCapturePhotoSettings()
        if videoCaptureDevice?.position == .back && videoCaptureDevice?.hasFlash == true {
            settings.flashMode = flashMode
        }
        
        // Set the correct orientation for the captured photo
        if let photoOutputConnection = photoOutput.connection(with: .video) {
            // Get the current device interface orientation
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let interfaceOrientation = windowScene.interfaceOrientation
            let isFrontCamera = videoCaptureDevice?.position == .front
            var rotationAngle: CGFloat
            
            switch interfaceOrientation {
            case .landscapeRight:
                rotationAngle = isFrontCamera ? 180.0 : 0.0
            case .landscapeLeft:
                rotationAngle = isFrontCamera ? 0.0 : 180.0
            case .portraitUpsideDown:
                rotationAngle = 270.0
            case .portrait, .unknown:
                rotationAngle = 90.0
            @unknown default:
                rotationAngle = 0.0
            }
            
            if photoOutputConnection.isVideoRotationAngleSupported(rotationAngle) {
                photoOutputConnection.videoRotationAngle = rotationAngle
            }
        }
        
        // Capture the photo with applied orientation settings
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private var flashMode: AVCaptureDevice.FlashMode = .off
    
    // New method to switch between physical lenses
    func switchToLens(with zoomFactor: CGFloat) {
        session.beginConfiguration()
        
        // Determine appropriate camera based on zoom factor
        let currentPosition = videoCaptureDevice?.position ?? .back
        var newCamera: AVCaptureDevice?
        var shouldApplyDigitalZoom = false
        
        // Determine which physical camera should be active based on zoom factor
        if currentPosition == .front {
            // Front camera lens selection
            if zoomFactor == 0.5 && frontUltraWideCamera != nil {
                newCamera = frontUltraWideCamera
            } else {
                newCamera = frontWideCamera
                // Apply digital zoom for front camera if zoom factor > 1.0
                shouldApplyDigitalZoom = zoomFactor > 1.0
            }
        } else {
            // Back camera lens selection based on zoom ranges
            if ultraWideZoomRange.contains(zoomFactor) && backUltraWideCamera != nil {
                // Ultrawide range: 0.5x - 0.9x
                newCamera = backUltraWideCamera
            } else if wideZoomRange.contains(zoomFactor) || backWideCamera != nil {
                // Wide range: 1.0x - 1.9x (or fallback if no other cameras available)
                newCamera = backWideCamera
                shouldApplyDigitalZoom = zoomFactor > 1.0
            } else if telephotoZoomRange.contains(zoomFactor) && backTelephotoCamera != nil {
                // Telephoto range: 2.0x and above with physical telephoto lens
                newCamera = backTelephotoCamera
                shouldApplyDigitalZoom = zoomFactor > CGFloat(maxTelephotoZoom)
            } else {
                // Digital zoom on wide lens if no telephoto available
                newCamera = backWideCamera
                shouldApplyDigitalZoom = true
            }
        }
        
        // Safely switch input
        guard let camera = newCamera,
              let newInput = try? AVCaptureDeviceInput(device: camera) else {
            // If we can't switch to the requested lens, restore the previous input
            if let device = videoCaptureDevice,
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            return
        }
        
        // Remove existing inputs
        session.inputs.forEach { session.removeInput($0) }
        
        videoCaptureDevice = camera
        
        if session.canAddInput(newInput) {
            session.addInput(newInput)
        }
        
        session.commitConfiguration()
        
        // Apply digital zoom if needed
        if shouldApplyDigitalZoom {
            zoom(with: zoomFactor)
        }
        
        // Force UI update to ensure toggle state is reflected immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // Focus and exposure control methods
    func focusAndExpose(at devicePoint: CGPoint) {
        guard let device = videoCaptureDevice else { return }
        
        do {
            print("Focus and Exposing")
            try device.lockForConfiguration()
            
            // Check if focus point of interest is supported
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            
            // Check if exposure point of interest is supported
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            
            // Reset exposure bias to 0
            exposureValue = 0.0
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Update UI with the focus point
            DispatchQueue.main.async {
                self.focusPoint = devicePoint
                self.showExposureSlider = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error focusing: \(error.localizedDescription)")
        }
    }
    
    func setExposureBias(_ bias: Float) {
        guard let device = videoCaptureDevice else {
            print("Video Capture Device is nil, cannot set exposure bias")
            return
        }
        
        do {
            print("Exposing")
            try device.lockForConfiguration()
            
            // Clamp the exposure bias within the device's supported range
            let minBias = device.minExposureTargetBias
            let maxBias = device.maxExposureTargetBias
            let clampedBias = max(minBias, min(bias, maxBias))
            
            // Apply the exposure bias immediately
            device.setExposureTargetBias(clampedBias) { (time) in
                // This completion handler is called when the exposure has been adjusted
                // Not using it for now, but available if needed
            }
            
            // Update the stored value - do this before unlocking for faster UI update
            DispatchQueue.main.async {
                self.exposureValue = clampedBias
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error setting exposure bias: \(error.localizedDescription)")
        }
    }
}

// Implement AVCapturePhotoCaptureDelegate to handle the captured photo
extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            completionHandler?(nil)
            return
        }
        
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completionHandler?(nil)
            return
        }
        
        // We've already set the orientation on the connection before capture,
        // so the image should already have the correct orientation
        completionHandler?(image)
    }
}

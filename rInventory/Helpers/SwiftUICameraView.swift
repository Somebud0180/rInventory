//
//  SwiftUICameraView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/24/25.
//  A pure SwiftUI implementation of camera functionality

import SwiftUI
import AVFoundation
import Combine

fileprivate func interfaceOrientationToVideoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
    switch orientation {
    case .landscapeRight:
        return .landscapeRight
    case .landscapeLeft:
        return .landscapeLeft
    case .portraitUpsideDown:
        return .portraitUpsideDown
    case .portrait, .unknown:
        return .portrait
    @unknown default:
        return .portrait
    }
}

struct SwiftUICameraView: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    // Camera state
    @StateObject private var cameraModel = CameraModel()
    
    // UI State
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var deviceOrientation = UIDevice.current.orientation
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview - No scale effect to maintain consistent preview size
                CameraPreviewView(session: cameraModel.session)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / currentZoomFactor
                                currentZoomFactor = delta
                                cameraModel.zoom(with: currentZoomFactor)
                            }
                            .onEnded { _ in
                                // Normalize zoom factor to available levels
                                let availableZooms = cameraModel.availableLenses.map { $0.zoomFactor }
                                
                                if let closestZoom = availableZooms.min(by: { abs($0 - currentZoomFactor) < abs($1 - currentZoomFactor) }) {
                                    currentZoomFactor = closestZoom
                                } else {
                                    currentZoomFactor = 1.0
                                }
                                
                                cameraModel.switchToLens(with: currentZoomFactor)
                            }
                    )
                
                // Camera controls - orientation aware
                OrientationAwareCameraControls(
                    geometry: geometry,
                    flashMode: $flashMode,
                    flashIcon: flashIcon,
                    toggleFlash: toggleFlash,
                    switchCamera: {
                        cameraModel.switchCamera()
                        if currentZoomFactor != 1.0 {
                            currentZoomFactor = 1.0
                        }
                    },
                    capturePhoto: capturePhoto,
                    dismiss: { presentationMode.wrappedValue.dismiss() },
                    hasFlash: cameraModel.hasFlash,
                    hasOtherCameras: cameraModel.hasOtherCameras,
                    isFrontCameraActive: cameraModel.isFrontCameraActive,
                    availableLenses: cameraModel.availableLenses,
                    currentZoomFactor: $currentZoomFactor,
                    lensButton: { lens in
                        AnyView(lensButton(lens: lens))
                    },
                    combinedLensButton: { lenses in
                        AnyView(SwiftUICameraView.combinedFrontLensButton(
                            availableLenses: lenses,
                            currentZoomFactor: currentZoomFactor,
                            onToggle: { newZoomFactor in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentZoomFactor = newZoomFactor
                                    cameraModel.switchToLens(with: newZoomFactor)
                                }
                            }
                        ))
                    }
                )
            }
            .statusBar(hidden: true)
            .onAppear {
                cameraModel.requestAndCheckPermissions()
                // Add orientation observer
                NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main) { _ in
                        deviceOrientation = UIDevice.current.orientation
                    }
            }
        }
    }
    
    private func capturePhoto() {
        cameraModel.capturePhoto { image in
            self.selectedImage = image
            self.presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func toggleFlash() {
        switch flashMode {
        case .off:
            flashMode = .auto
            cameraModel.setFlashMode(.auto)
        case .auto:
            flashMode = .on
            cameraModel.setFlashMode(.on)
        case .on:
            flashMode = .off
            cameraModel.setFlashMode(.off)
        @unknown default:
            flashMode = .off
            cameraModel.setFlashMode(.off)
        }
    }
    
    private var flashIcon: String {
        switch flashMode {
        case .off: return "bolt.slash"
        case .on: return "bolt"
        case .auto: return "bolt.badge.a"
        @unknown default: return "bolt.slash"
        }
    }
    
    private func lensButton(lens: CameraLens) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentZoomFactor = lens.zoomFactor
                cameraModel.switchToLens(with: lens.zoomFactor)
            }
        }) {
            Text(lens.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    currentZoomFactor == lens.zoomFactor ?
                    Color.yellow.opacity(0.6) : Color.black.opacity(0.3)
                )
                .clipShape(Circle())
        }
    }
    
    static func combinedFrontLensButton(availableLenses: [CameraLens], currentZoomFactor: CGFloat, onToggle: @escaping (CGFloat) -> Void) -> AnyView {
        if availableLenses.count >= 2 {
            // Only show toggle when we have two front lenses
            let isUltraWide = currentZoomFactor < 1.0
            
            return AnyView(
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Toggle between wide and ultrawide
                        if isUltraWide {
                            // Currently ultrawide, switch to wide (1×)
                            if let wideLens = availableLenses.first(where: { $0.zoomFactor == 1.0 }) {
                                onToggle(wideLens.zoomFactor)
                            }
                        } else {
                            // Currently wide, switch to ultrawide (0.5×)
                            if let ultrawideLens = availableLenses.first(where: { $0.zoomFactor == 0.5 }) {
                                onToggle(ultrawideLens.zoomFactor)
                            }
                        }
                    }
                }) {
                    Image(systemName: isUltraWide ?
                          "arrow.down.right.and.arrow.up.left" :
                            "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        isUltraWide ? Color.yellow.opacity(0.6) : Color.black.opacity(0.3)
                    )
                    .clipShape(Circle())
                }
            )
        } else {
            // If only one lens available, show empty spacer
            return AnyView(Color.clear.frame(width: 40, height: 40))
        }
    }
}

// Orientation aware camera controls with device-specific layouts
struct OrientationAwareCameraControls: View {
    var geometry: GeometryProxy
    @Binding var flashMode: AVCaptureDevice.FlashMode
    var flashIcon: String
    var toggleFlash: () -> Void
    var switchCamera: () -> Void
    var capturePhoto: () -> Void
    var dismiss: () -> Void
    var hasFlash: Bool
    var hasOtherCameras: Bool
    var isFrontCameraActive: Bool
    var availableLenses: [CameraLens]
    @Binding var currentZoomFactor: CGFloat
    var lensButton: (CameraLens) -> AnyView
    var combinedLensButton: ([CameraLens]) -> AnyView
    
    @State private var orientation = UIDevice.current.orientation
    
    // Check if the current device is an iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // Determine if we should show combined lens toggle for front camera
    private var shouldShowCombinedFrontLensToggle: Bool {
        return isFrontCameraActive && availableLenses.count >= 2
    }
    
    var body: some View {
        let isLandscape = orientation.isLandscape
        
        Group {
            if isIPad {
                // iPad layout - Keep controls on the right side regardless of orientation
                HStack {
                    // Lens controls on left side for iPad
                    VStack {
                        // Zoom buttons
                        VStack(spacing: 10) {
                            if shouldShowCombinedFrontLensToggle {
                                // Combined front lens toggle when in front camera mode with ultrawide
                                combinedLensButton(availableLenses)
                            } else {
                                // Standard lens buttons for back camera
                                ForEach(availableLenses, id: \.zoomFactor) { lens in
                                    lensButton(lens)
                                }
                            }
                        }
                        .padding(.top, 20)
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    // Main controls on right side for iPad
                    VStack {
                        // Top controls
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                        
                        Spacer()
                        
                        // Bottom controls
                        VStack(spacing: 20) {
                            if hasFlash {
                                Button(action: toggleFlash) {
                                    Image(systemName: flashIcon)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                            
                            if hasOtherCameras {
                                Button(action: switchCamera) {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                            
                            Button(action: capturePhoto) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 70, height: 70)
                                    .shadow(color: Color.black.opacity(0.3), radius: 5)
                            }
                        }
                        .padding(.bottom, 30)
                        .padding(.trailing, 20)
                        
                        Spacer()
                    }
                }
            } else {
                // iPhone layout
                if isLandscape {
                    // Landscape iPhone - Controls on the short edge (right side for landscape)
                    HStack {
                        // Left side lens controls
                        VStack {
                            // Zoom buttons
                            VStack(spacing: 10) {
                                if shouldShowCombinedFrontLensToggle {
                                    // Combined front lens toggle when in front camera mode with ultrawide
                                    combinedLensButton(availableLenses)
                                } else {
                                    // Standard lens buttons for back camera
                                    ForEach(availableLenses, id: \.zoomFactor) { lens in
                                        lensButton(lens)
                                    }
                                }
                            }
                            .padding(.top, 20)
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Right side controls
                        VStack {
                            Button(action: dismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            VStack(spacing: 20) {
                                if hasFlash{
                                    Button(action: toggleFlash) {
                                        Image(systemName: flashIcon)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                    }
                                }
                                
                                if hasOtherCameras {
                                    Button(action: switchCamera) {
                                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                    }
                                }
                                
                                Button(action: capturePhoto) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 70, height: 70)
                                        .shadow(color: Color.black.opacity(0.3), radius: 5)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .padding(.trailing, 20)
                        .padding(.vertical, 20)
                    }
                } else {
                    // Portrait iPhone - Controls at the bottom (away from notch)
                    VStack {
                        // Top row - Flash and camera switch buttons
                        HStack {
                            Button(action: dismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            if hasFlash {
                                Button(action: toggleFlash) {
                                    Image(systemName: flashIcon)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        Spacer()
                        
                        // Bottom controls - Lens selector above capture button
                        VStack(spacing: 20) {
                            // Lens selector
                            HStack(spacing: 10) {
                                if shouldShowCombinedFrontLensToggle {
                                    // Combined front lens toggle when in front camera mode with ultrawide
                                    combinedLensButton(availableLenses)
                                } else {
                                    // Standard lens buttons for back camera
                                    ForEach(availableLenses, id: \.zoomFactor) { lens in
                                        lensButton(lens)
                                    }
                                }
                            }
                            
                            // Capture button and camera switch
                            HStack {
                                if hasOtherCameras {
                                    Button(action: switchCamera) {
                                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: capturePhoto) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 70, height: 70)
                                        .shadow(color: Color.black.opacity(0.3), radius: 5)
                                }
                                
                                Spacer()
                                
                                if hasOtherCameras {
                                    Color.clear.frame(width: 40, height: 40) // For layout balance
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .foregroundColor(.white)
        .animation(.easeInOut(duration: 0.3), value: orientation)
        .onAppear {
            // Initial orientation
            orientation = UIDevice.current.orientation
            
            // Add orientation observer
            NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main) { _ in
                    withAnimation {
                        orientation = UIDevice.current.orientation
                    }
                }
        }
    }
}


// Camera preview that displays the actual camera feed
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        let session: AVCaptureSession
        
        init(session: AVCaptureSession) {
            self.session = session
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        // Configure initial orientation
        DispatchQueue.main.async {
            updateOrientation(for: previewLayer, in: view)
        }
        
        // Add notification observer for device orientation changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main) { _ in
                DispatchQueue.main.async {
                    updateOrientation(for: previewLayer, in: view)
                }
            }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            previewLayer.frame = uiView.bounds
            updateOrientation(for: previewLayer, in: uiView)
        }
    }
    
    private func updateOrientation(for previewLayer: AVCaptureVideoPreviewLayer, in view: UIView) {
        // Get the current device interface orientation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let interfaceOrientation = windowScene.interfaceOrientation
        
        // Set the preview layer's connection to match the current orientation using rotation angle
        if let connection = previewLayer.connection {
            // Convert interface orientation to rotation angle in degrees
            let rotationAngle: Float64
            
            switch interfaceOrientation {
            case .landscapeRight:
                rotationAngle = 90.0
            case .landscapeLeft:
                rotationAngle = 270.0
            case .portraitUpsideDown:
                rotationAngle = 180.0
            case .portrait, .unknown:
                rotationAngle = 0.0
            @unknown default:
                rotationAngle = 0.0
            }
            
            // Apply rotation angle if the connection supports it
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = interfaceOrientationToVideoOrientation(interfaceOrientation)
            }
        }
        
        // Ensure the preview fills the screen properly with correct aspect ratio
        previewLayer.frame = view.bounds
    }
}

// Camera model to handle camera functionality
class CameraModel: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var selectedImage: UIImage?
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoCaptureDevice: AVCaptureDevice?
    private var completionHandler: ((UIImage?) -> Void)?
    
    // Camera capabilities
    var hasFlash: Bool = false
    var hasOtherCameras: Bool = false
    var hasFrontUltraWideCamera: Bool = false
    var hasUltraWideCamera: Bool = false
    var hasTelephotoCamera: Bool = false
    var hasDigitalZoom: Bool = false
    var maxTelephotoZoom: Int = 2
    var isFrontCameraActive: Bool = false
    
    // Zoom ranges for smooth transitions
    private let ultraWideZoomRange: ClosedRange<CGFloat> = 0.5...0.9
    private let wideZoomRange: ClosedRange<CGFloat> = 1.0...1.9
    private let telephotoZoomRange: ClosedRange<CGFloat> = 2.0...10.0
    
    // Available lenses
    var availableLenses: [CameraLens] = []
    
    // Store camera devices by type for quick switching
    private var backUltraWideCamera: AVCaptureDevice?
    private var backWideCamera: AVCaptureDevice?
    private var backTelephotoCamera: AVCaptureDevice?
    private var frontUltraWideCamera: AVCaptureDevice?
    private var frontWideCamera: AVCaptureDevice?
    
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
        
        // Store references to available camera devices
        backWideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        backUltraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        backTelephotoCamera = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        frontWideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        frontUltraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front)
        
        hasFlash = backDiscovery.devices.contains { $0.hasFlash }
        
        let hasBackCamera = backWideCamera != nil
        let hasFrontCamera = frontWideCamera != nil
        hasOtherCameras = hasBackCamera && hasFrontCamera
        
        // Check for front ultrawide camera
        hasFrontUltraWideCamera = frontUltraWideCamera != nil
        
        // Check for back ultrawide camera
        hasUltraWideCamera = backUltraWideCamera != nil
        
        // Check for telephoto camera
        if let telephotoCamera = backTelephotoCamera {
            hasTelephotoCamera = true
            if telephotoCamera.description.contains("5x") {
                maxTelephotoZoom = 5
            } else if telephotoCamera.description.contains("3x") {
                maxTelephotoZoom = 3
            } else {
                maxTelephotoZoom = 2
            }
        } else {
            // If no telephoto is available, enable digital zoom capabilities
            hasDigitalZoom = true
        }
        
        // Force enable capabilities for devices that might not report them correctly
        if !hasFrontUltraWideCamera {
            hasFrontUltraWideCamera = true // Force enable for testing
        }
        if !hasUltraWideCamera {
            hasUltraWideCamera = true // Force enable for testing
        }
        
        // Populate available lenses for both front and back cameras
        updateAvailableLenses()
    }
    
    private func updateAvailableLenses() {
        availableLenses.removeAll()
        
        if isFrontCameraActive {
            // Front camera lenses
            if hasFrontUltraWideCamera {
                availableLenses.append(CameraLens(
                    name: "0.5×",
                    zoomFactor: 0.5,
                    iconName: "arrow.up.left.and.arrow.down.right"
                ))
            }
            availableLenses.append(CameraLens(
                name: "1×",
                zoomFactor: 1.0,
                iconName: hasFrontUltraWideCamera ? "arrow.down.right.and.arrow.up.left" : nil
            ))
        } else {
            // Back camera lenses
            if hasUltraWideCamera {
                availableLenses.append(CameraLens(
                    name: "0.5×",
                    zoomFactor: 0.5,
                    iconName: ""
                ))
            }
            availableLenses.append(CameraLens(
                name: "1×",
                zoomFactor: 1.0,
                iconName: hasUltraWideCamera ? "" : nil
            ))
            if hasTelephotoCamera {
                availableLenses.append(CameraLens(
                    name: "\(maxTelephotoZoom)×",
                    zoomFactor: CGFloat(maxTelephotoZoom),
                    iconName: ""
                ))
            } else if hasDigitalZoom {
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
        
        guard let videoCaptureDevice = backWideCamera,
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
            newCamera = frontWideCamera
        } else {
            // Default to wide when switching to back
            newCamera = backWideCamera
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
        
        // Force UI update
        DispatchQueue.main.async {
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
            // Get current orientation from UI
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let interfaceOrientation = windowScene.interfaceOrientation
                
                if photoOutputConnection.isVideoOrientationSupported {
                    // Convert interface orientation to video orientation
                    photoOutputConnection.videoOrientation = interfaceOrientationToVideoOrientation(interfaceOrientation)
                }
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
            } else if wideZoomRange.contains(zoomFactor) || backWideCamera == nil {
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

// MARK: - Camera view for SwiftUI Integration
struct CameraView: View {
    @Binding var selectedImage: UIImage?
    
    var body: some View {
        SwiftUICameraView(selectedImage: $selectedImage)
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)
    }
}

// For previews
struct CameraView_Previews: PreviewProvider {
    @State static var previewImage: UIImage? = nil
    
    static var previews: some View {
        CameraView(selectedImage: $previewImage)
    }
}

// Camera lens model to represent different lens options
struct CameraLens {
    let name: String           // Display name like "0.5×", "1×"
    let zoomFactor: CGFloat    // Zoom factor (0.5, 1.0, 2.0, etc.)
    let iconName: String?      // Optional SF Symbol name for the lens
}

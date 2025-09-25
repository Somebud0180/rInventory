//
//  SwiftUICameraView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/24/25.
//  A pure SwiftUI implementation of camera functionality

import SwiftUI
import AVFoundation
import Combine

// Camera lens model to represent different lens options
struct CameraLens {
    let name: String           // Display name like "0.5×", "1×"
    let zoomFactor: CGFloat    // Zoom factor (0.5, 1.0, 2.0, etc.)
    let iconName: String?      // Optional SF Symbol name for the lens
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
    
    // Constants for exposure slider
    private let sliderMinValue: Float = -2.0
    private let sliderMaxValue: Float = 2.0
    private let sliderStep: Float = 0.1
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview with tap to focus
                CameraPreviewView(session: cameraModel.session, onTap: { point in
                    cameraModel.focusAndExpose(at: point)
                })
                .ignoresSafeArea()
//                .gesture(
//                    MagnificationGesture()
//                        .onChanged { value in
//                            let delta = value / currentZoomFactor
//                            currentZoomFactor = delta
//                            cameraModel.zoom(with: currentZoomFactor)
//                        }
//                        .onEnded { _ in
//                            let availableZooms = cameraModel.availableLenses.map { $0.zoomFactor }
//                            // Find the closest lens zoom
//                            if let closestZoom = availableZooms.min(by: { abs($0 - currentZoomFactor) < abs($1 - currentZoomFactor) }) {
//                                // Only snap to a new lens if the closest zoom is different (by threshold) from the current zoom factor
//                                // Here, define a threshold for when to snap (e.g., 0.1)
//                                let snapThreshold: CGFloat = 0.1
//                                if abs(closestZoom - currentZoomFactor) <= snapThreshold {
//                                    // Close enough to a lens: snap and switch to that lens
//                                    currentZoomFactor = closestZoom
//                                    cameraModel.switchToLens(with: currentZoomFactor)
//                                }
//                            } else {
//                                // Fallback to 1.0 if no lens found
//                                currentZoomFactor = 1.0
//                                cameraModel.switchToLens(with: currentZoomFactor)
//                            }
//                        }
//                )
                
                // Replace separate focus and exposure components with the combined FocusExposureView
                if let point = cameraModel.focusPoint {
                    FocusExposureView(
                        point: point,
                        exposureValue: $cameraModel.exposureValue,
                        onExposureChange: { bias in
                            cameraModel.setExposureBias(bias)
                        },
                        showExposure: cameraModel.showExposureSlider
                    )
                }
                
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
            // Global exposure adjustment gesture - active when slider is visible
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Only handle the drag gesture if the exposure slider is visible
                        guard cameraModel.showExposureSlider else { return }
                        
                        // Use only vertical movement for exposure adjustment
                        let screenHeight = geometry.size.height
                        
                        // Calculate the vertical percentage, ignoring horizontal movement
                        let percent = 1 - (gesture.location.y / screenHeight).clamped(to: 0...1)
                        
                        // Map percentage to exposure bias range
                        let newValue = sliderMinValue + Float(percent) * (sliderMaxValue - sliderMinValue)
                        let steppedValue = (newValue / sliderStep).rounded() * sliderStep
                        let finalValue = max(sliderMinValue, min(sliderMaxValue, steppedValue))
                        
                        // Update the model in real-time
                        if cameraModel.exposureValue != finalValue {
                            cameraModel.exposureValue = finalValue
                            cameraModel.setExposureBias(finalValue)
                        }
                    }
            )
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
    var onTap: ((CGPoint) -> Void)?
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        let session: AVCaptureSession
        var onTap: ((CGPoint) -> Void)?
        
        init(session: AVCaptureSession, onTap: ((CGPoint) -> Void)?) {
            self.session = session
            self.onTap = onTap
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewLayer = previewLayer else { return }
            
            let touchPoint = gesture.location(in: gesture.view)
            // Convert the touch point from the view's coordinate system to the coordinate system of the preview layer
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)
            
            // Pass the normalized device point to the handler
            onTap?(devicePoint)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onTap: onTap)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
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
    
    // Helper to get the current capture device from the session
    private func currentVideoCaptureDevice(from session: AVCaptureSession) -> AVCaptureDevice? {
        return (session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first)?.device
    }
    
    private func updateOrientation(for previewLayer: AVCaptureVideoPreviewLayer, in view: UIView) {
        // Get the current device interface orientation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let interfaceOrientation = windowScene.interfaceOrientation
        let isFrontCamera = currentVideoCaptureDevice(from: session)?.position == .front
        
        if let connection = previewLayer.connection {
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
            
            // Apply rotation angle if the connection supports it
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }
        
        // Ensure the preview fills the screen properly with correct aspect ratio
        previewLayer.frame = view.bounds
    }
}

// MARK: - Camera view for SwiftUI Integration
struct CameraView: View {
    @Binding var selectedImage: UIImage?
    
    var body: some View {
        SwiftUICameraView(selectedImage: $selectedImage)
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

// MARK: - Extensions
// Extension for clamping values within a range
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}


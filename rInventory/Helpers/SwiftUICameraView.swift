//
//  SwiftUICameraView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/22/25.
//  A SwiftUI-friendly implementation of camera functionality

import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera Handling for SwiftUI
struct SwiftUICameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = PortraitOnlyCameraController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.showsCameraControls = false
        
        // Force camera to maintain portrait orientation
        picker.cameraCaptureMode = .photo
        picker.cameraViewTransform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        
        // Create our custom overlay
        let overlayView = SwiftUICameraOverlayView(frame: picker.view.frame)
        overlayView.imagePickerController = picker
        overlayView.onImageCaptured = { capturedImage in
            self.image = capturedImage
            self.presentationMode.wrappedValue.dismiss()
        }
        picker.cameraOverlayView = overlayView
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        if let overlayView = uiViewController.cameraOverlayView as? SwiftUICameraOverlayView {
            overlayView.frame = uiViewController.view.bounds
            
            // Force proper layout on each update
            DispatchQueue.main.async {
                overlayView.fixCameraPreview()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SwiftUICameraView
        
        init(_ parent: SwiftUICameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Camera Overlay View for SwiftUI
class SwiftUICameraOverlayView: UIView {
    // UI Elements
    private let captureButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let zoomWideButton = UIButton(type: .system)
    private let zoom1xButton = UIButton(type: .system)
    private let zoom2xButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    
    // Zoom button container
    private let zoomButtonStackView = UIStackView()
    
    // Fixed UI container to prevent rotation of button positions
    private let buttonContainer = UIView()
    
    // Properties
    weak var imagePickerController: UIImagePickerController?
    private var currentZoom: CGFloat = 1.0
    var onImageCaptured: ((UIImage?) -> Void)?
    
    // Haptic feedback generator
    private let hapticFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Zoom properties
    private var lastZoomFactor: CGFloat = 1.0
    
    // Orientation tracking
    private var currentDeviceOrientation: UIDeviceOrientation = .portrait
    
    // Screen metrics for proper centering
    private var screenWidth: CGFloat = UIScreen.main.bounds.width
    private var screenHeight: CGFloat = UIScreen.main.bounds.height
    
    // Available zoom levels based on device capabilities
    private var availableZoomLevels: [CGFloat] = [1.0]
    
    // Base scale to make 4:3 camera preview fill a tall portrait screen
    private func cameraBaseScale() -> CGFloat {
        let size = bounds.size
        let w = min(size.width, size.height)
        let h = max(size.width, size.height)
        let screenAspect = h / max(w, 1)
        let cameraAspect: CGFloat = 4.0 / 3.0
        // If screen is taller than 4:3, scale up to fill height
        return max(1.0, screenAspect / cameraAspect)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        updateScreenMetrics()
        setupUI()
        setupOrientationObserver()
        setupPinchGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateScreenMetrics()
        setupUI()
        setupOrientationObserver()
        setupPinchGesture()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func updateScreenMetrics() {
        // Always use portrait orientation metrics
        screenWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        screenHeight = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }
    
    private func setupOrientationObserver() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        currentDeviceOrientation = UIDevice.current.orientation
    }
    
    private func setupPinchGesture() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
        addGestureRecognizer(pinchGesture)
    }
    
    @objc private func handlePinchToZoom(_ gesture: UIPinchGestureRecognizer) {
        guard imagePickerController != nil else { return }
        let newScale = gesture.scale * lastZoomFactor
        let minZoom: CGFloat = availableZoomLevels.min() ?? 1.0
        let maxZoom: CGFloat = 10.0
        currentZoom = max(minZoom, min(newScale, maxZoom))
        switch gesture.state {
        case .began:
            hapticFeedbackGenerator.prepare()
        case .changed:
            applyZoom(currentZoom, animated: false)
        case .ended, .cancelled:
            lastZoomFactor = currentZoom
        default:
            break
        }
    }
    
    @objc private func handleOrientationChange() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isValidInterfaceOrientation {
            currentDeviceOrientation = deviceOrientation
            rotateButtonsForCurrentOrientation()
            DispatchQueue.main.async {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
    }
    
    private func rotateButtonsForCurrentOrientation() {
        var rotationAngle: CGFloat = 0.0
        switch currentDeviceOrientation {
        case .landscapeLeft:
            rotationAngle = -CGFloat.pi / 2
        case .landscapeRight:
            rotationAngle = CGFloat.pi / 2
        case .portraitUpsideDown:
            rotationAngle = CGFloat.pi
        default:
            rotationAngle = 0.0
        }
        UIView.animate(withDuration: 0.25) {
            self.flashButton.imageView?.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.switchCameraButton.imageView?.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.cancelButton.imageView?.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.captureButton.imageView?.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.zoomButtonStackView.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
    }
    
    func fixCameraPreview() {
        // No-op now; let UIImagePickerController manage preview layout. We only ensure layout updates.
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    // Detect available camera lenses on the device using AVFoundation
    private func detectAvailableCameraLenses() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        var zoomLevels: [CGFloat] = []
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) { zoomLevels.append(0.5) }
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInWideAngleCamera }) { zoomLevels.append(1.0) }
        if let tele = discoverySession.devices.first(where: { $0.deviceType == .builtInTelephotoCamera }) {
            if tele.description.contains("5x") { zoomLevels.append(5.0) }
            else if tele.description.contains("3x") { zoomLevels.append(3.0) }
            else { zoomLevels.append(2.0) }
        }
        if zoomLevels.isEmpty { zoomLevels.append(1.0) }
        availableZoomLevels = zoomLevels.sorted()
        updateZoomButtonsVisibility()
    }
    
    private func updateZoomButtonsVisibility() {
        zoomWideButton.isHidden = !availableZoomLevels.contains(0.5)
        zoom1xButton.isHidden = !availableZoomLevels.contains(1.0)
        let telephotoZooms = availableZoomLevels.filter { $0 > 1.0 }
        zoom2xButton.isHidden = telephotoZooms.isEmpty
        zoomWideButton.setTitle("0.5×", for: .normal)
        zoom1xButton.setTitle("1×", for: .normal)
        if let maxZoom = telephotoZooms.max() { zoom2xButton.setTitle("\(Int(maxZoom))×", for: .normal) } else { zoom2xButton.setTitle("2×", for: .normal) }
        updateZoomButtonHighlight()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = .clear
        addSubview(buttonContainer)
        
        captureButton.setImage(UIImage(systemName: "circle.fill"), for: .normal)
        captureButton.tintColor = .white
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.clipsToBounds = true
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(captureButton)
        
        flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        flashButton.layer.cornerRadius = 20
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(flashButton)
        
        switchCameraButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        switchCameraButton.tintColor = .white
        switchCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        switchCameraButton.layer.cornerRadius = 20
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(switchCameraButton)
        
        configureZoomButton(zoomWideButton, title: "0.5×", action: #selector(setWideZoom))
        configureZoomButton(zoom1xButton, title: "1×", action: #selector(setNormalZoom))
        configureZoomButton(zoom2xButton, title: "2×", action: #selector(setTelephotoZoom))
        
        zoomButtonStackView.axis = .horizontal
        zoomButtonStackView.spacing = 10
        zoomButtonStackView.distribution = .fillEqually
        zoomButtonStackView.translatesAutoresizingMaskIntoConstraints = false
        zoomButtonStackView.addArrangedSubview(zoomWideButton)
        zoomButtonStackView.addArrangedSubview(zoom1xButton)
        zoomButtonStackView.addArrangedSubview(zoom2xButton)
        buttonContainer.addSubview(zoomButtonStackView)
        
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        cancelButton.layer.cornerRadius = 20
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(cancelButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            buttonContainer.topAnchor.constraint(equalTo: topAnchor),
            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40),
            flashButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            flashButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            
            switchCameraButton.widthAnchor.constraint(equalToConstant: 40),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 40),
            switchCameraButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            switchCameraButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            
            zoomWideButton.widthAnchor.constraint(equalToConstant: 40),
            zoomWideButton.heightAnchor.constraint(equalToConstant: 40),
            zoom1xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom1xButton.heightAnchor.constraint(equalToConstant: 40),
            zoom2xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom2xButton.heightAnchor.constraint(equalToConstant: 40),
            
            cancelButton.widthAnchor.constraint(equalToConstant: 40),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            cancelButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        setupPortraitConstraints()
    }
    
    private func configureZoomButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupPortraitConstraints() {
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -30),
            zoomButtonStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            zoomButtonStackView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20)
        ])
    }
    
    @objc private func capturePhoto() {
        imagePickerController?.takePicture()
    }
    
    @objc private func toggleFlash() {
        guard let picker = imagePickerController else { return }
        if picker.cameraFlashMode == .off {
            picker.cameraFlashMode = .auto
            flashButton.setImage(UIImage(systemName: "bolt.badge.a"), for: .normal)
        } else if picker.cameraFlashMode == .auto {
            picker.cameraFlashMode = .on
            flashButton.setImage(UIImage(systemName: "bolt"), for: .normal)
        } else {
            picker.cameraFlashMode = .off
            flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        }
    }
    
    @objc private func switchCamera() {
        guard let picker = imagePickerController else { return }
        picker.cameraDevice = (picker.cameraDevice == .rear) ? .front : .rear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.detectAvailableCameraLenses()
            self.setNormalZoom()
        }
    }
    
    @objc private func setWideZoom() {
        if availableZoomLevels.contains(0.5) {
            applyZoom(0.5, animated: true)
            hapticFeedbackGenerator.impactOccurred()
        }
    }
    
    @objc private func setNormalZoom() {
        applyZoom(1.0, animated: true)
        hapticFeedbackGenerator.impactOccurred()
    }
    
    @objc private func setTelephotoZoom() {
        if let maxZoom = availableZoomLevels.filter({ $0 > 1.0 }).max() {
            applyZoom(maxZoom, animated: true)
            hapticFeedbackGenerator.impactOccurred()
        }
    }
    
    private func applyZoom(_ zoomLevel: CGFloat, animated: Bool = true) {
        guard let picker = imagePickerController else { return }
        if hasCrossedZoomThreshold(lastZoomFactor, newZoom: zoomLevel) {
            hapticFeedbackGenerator.impactOccurred()
        }
        currentZoom = zoomLevel
        lastZoomFactor = zoomLevel
        let scale = cameraBaseScale() * zoomLevel
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        if animated {
            UIView.animate(withDuration: 0.2) { picker.cameraViewTransform = transform }
        } else {
            picker.cameraViewTransform = transform
        }
        updateZoomButtonHighlight()
    }
    
    private func hasCrossedZoomThreshold(_ oldZoom: CGFloat, newZoom: CGFloat) -> Bool {
        let thresholds: [CGFloat] = [0.5, 1.0, 2.0, 3.0]
        return thresholds.contains { (oldZoom < $0 && newZoom >= $0) || (oldZoom >= $0 && newZoom < $0) }
    }
    
    private func updateZoomButtonHighlight() {
        zoomWideButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoom1xButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoom2xButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        let zoomPresets = availableZoomLevels
        var closest = zoomPresets.first ?? 1.0
        var minDiff = abs(currentZoom - closest)
        for preset in zoomPresets {
            let diff = abs(currentZoom - preset)
            if diff < minDiff { minDiff = diff; closest = preset }
        }
        if closest == 0.5 && availableZoomLevels.contains(0.5) {
            zoomWideButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        } else if closest == 1.0 {
            zoom1xButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        } else if closest > 1.0 && !zoom2xButton.isHidden {
            zoom2xButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        }
    }
    
    @objc private func cancel() {
        imagePickerController?.dismiss(animated: true, completion: nil)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateScreenMetrics()
        rotateButtonsForCurrentOrientation()
        // Ensure the preview stays centered and correctly scaled on size/orientation changes
        applyZoom(currentZoom, animated: false)
    }
}

// MARK: - Custom Camera Controller
class PortraitOnlyCameraController: UIImagePickerController {
    // Override the supportedInterfaceOrientations to force portrait orientation
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // Override the preferredInterfaceOrientationForPresentation to set initial orientation
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    // Prevent auto-rotation
    override var shouldAutorotate: Bool {
        return false
    }
}

// MARK: - SwiftUI Camera Implementation
struct CameraViewUI: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        SwiftUICameraView(image: $selectedImage)
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)
            .lockDeviceOrientation(.portrait)
    }
}

// For previews
struct CameraViewUI_Previews: PreviewProvider {
    @State static var previewImage: UIImage? = nil
    
    static var previews: some View {
        CameraViewUI(selectedImage: $previewImage)
    }
}

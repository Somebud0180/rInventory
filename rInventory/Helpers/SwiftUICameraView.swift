// SwiftUICameraView.swift
// A SwiftUI-friendly implementation of camera functionality

import SwiftUI
import UIKit

// MARK: - Camera Handling for SwiftUI
struct SwiftUICameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.showsCameraControls = false
        
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
    
    // Properties
    weak var imagePickerController: UIImagePickerController?
    private var currentZoom: CGFloat = 1.0
    var onImageCaptured: ((UIImage?) -> Void)?
    
    // Observation timer to fix layout issues
    private var layoutTimer: Timer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupLayoutTimer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupLayoutTimer()
    }
    
    deinit {
        layoutTimer?.invalidate()
    }
    
    private func setupLayoutTimer() {
        // Create a timer that periodically checks and fixes the camera preview
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.fixCameraPreview()
        }
    }
    
    func fixCameraPreview() {
        adjustCameraPreviewPosition()
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func setupUI() {
        // Make the view transparent for camera content to be visible
        backgroundColor = UIColor.clear
        
        // Configure capture button (large circular button)
        captureButton.setImage(UIImage(systemName: "circle.fill"), for: .normal)
        captureButton.tintColor = .white
        captureButton.backgroundColor = .systemRed
        captureButton.layer.cornerRadius = 35
        captureButton.clipsToBounds = true
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captureButton)
        
        // Configure flash button
        flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        flashButton.layer.cornerRadius = 20
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flashButton)
        
        // Configure camera switch button
        switchCameraButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        switchCameraButton.tintColor = .white
        switchCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        switchCameraButton.layer.cornerRadius = 20
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(switchCameraButton)
        
        // Configure zoom buttons
        zoomWideButton.setTitle("0.5×", for: .normal)
        zoomWideButton.tintColor = .white
        zoomWideButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoomWideButton.layer.cornerRadius = 20
        zoomWideButton.addTarget(self, action: #selector(setWideZoom), for: .touchUpInside)
        zoomWideButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomWideButton)
        
        zoom1xButton.setTitle("1×", for: .normal)
        zoom1xButton.tintColor = .white
        zoom1xButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6) // Highlighted by default
        zoom1xButton.layer.cornerRadius = 20
        zoom1xButton.addTarget(self, action: #selector(setNormalZoom), for: .touchUpInside)
        zoom1xButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoom1xButton)
        
        zoom2xButton.setTitle("2×", for: .normal)
        zoom2xButton.tintColor = .white
        zoom2xButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoom2xButton.layer.cornerRadius = 20
        zoom2xButton.addTarget(self, action: #selector(setTelephotoZoom), for: .touchUpInside)
        zoom2xButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoom2xButton)
        
        // Configure cancel button
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        cancelButton.layer.cornerRadius = 20
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        // We'll set up adaptive constraints that work in both portrait and landscape
        NSLayoutConstraint.activate([
            // Capture button size
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Flash button top left
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40),
            flashButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            flashButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            
            // Switch camera button top right
            switchCameraButton.widthAnchor.constraint(equalToConstant: 40),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 40),
            switchCameraButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            switchCameraButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            
            // Zoom buttons - we'll set position based on orientation
            zoomWideButton.widthAnchor.constraint(equalToConstant: 40),
            zoomWideButton.heightAnchor.constraint(equalToConstant: 40),
            
            zoom1xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom1xButton.heightAnchor.constraint(equalToConstant: 40),
            
            zoom2xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom2xButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Cancel button
            cancelButton.widthAnchor.constraint(equalToConstant: 40),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
        updateConstraintsForCurrentOrientation()
    }
    
    @objc private func capturePhoto() {
        guard let picker = imagePickerController else { return }
        
        picker.takePicture()
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
        
        // Toggle between front and back camera
        if picker.cameraDevice == .rear {
            picker.cameraDevice = .front
        } else {
            picker.cameraDevice = .rear
        }
    }
    
    @objc private func setWideZoom() {
        currentZoom = 0.5
        updateZoomButtonHighlight()
    }
    
    @objc private func setNormalZoom() {
        currentZoom = 1.0
        updateZoomButtonHighlight()
    }
    
    @objc private func setTelephotoZoom() {
        currentZoom = 2.0
        updateZoomButtonHighlight()
    }
    
    private func updateZoomButtonHighlight() {
        // Reset all zoom button backgrounds
        zoomWideButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoom1xButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoom2xButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        
        // Highlight the active zoom button
        if currentZoom == 0.5 {
            zoomWideButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        } else if currentZoom == 1.0 {
            zoom1xButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        } else if currentZoom == 2.0 {
            zoom2xButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
        }
    }
    
    @objc private func cancel() {
        imagePickerController?.dismiss(animated: true, completion: nil)
    }
    
    // Called when orientation changes
    override func layoutSubviews() {
        super.layoutSubviews()
        updateConstraintsForCurrentOrientation()
        adjustCameraPreviewPosition()
    }
    
    private func updateConstraintsForCurrentOrientation() {
        // Remove existing dynamic constraints
        constraints.forEach { constraint in
            if constraint.firstItem === captureButton &&
                (constraint.firstAttribute == .centerX ||
                 constraint.firstAttribute == .centerY ||
                 constraint.firstAttribute == .trailing ||
                 constraint.firstAttribute == .bottom) {
                removeConstraint(constraint)
            }
            
            if (constraint.firstItem === zoomWideButton || constraint.firstItem === zoom1xButton || constraint.firstItem === zoom2xButton) &&
                (constraint.firstAttribute == .top || constraint.firstAttribute == .centerY ||
                 constraint.firstAttribute == .leading || constraint.firstAttribute == .trailing ||
                 constraint.firstAttribute == .centerX || constraint.firstAttribute == .bottom) {
                removeConstraint(constraint)
            }
        }
        
        // Get current orientation
        let isLandscape = frame.width > frame.height
        
        if isLandscape {
            // Landscape layout
            NSLayoutConstraint.activate([
                captureButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -30),
                captureButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                
                // Zoom buttons vertically on right side
                zoom1xButton.trailingAnchor.constraint(equalTo: captureButton.leadingAnchor, constant: -30),
                zoom1xButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                
                zoomWideButton.trailingAnchor.constraint(equalTo: zoom1xButton.trailingAnchor),
                zoomWideButton.bottomAnchor.constraint(equalTo: zoom1xButton.topAnchor, constant: -15),
                
                zoom2xButton.trailingAnchor.constraint(equalTo: zoom1xButton.trailingAnchor),
                zoom2xButton.topAnchor.constraint(equalTo: zoom1xButton.bottomAnchor, constant: 15)
            ])
        } else {
            // Portrait layout
            NSLayoutConstraint.activate([
                captureButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                captureButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -30),
                
                // Zoom buttons horizontally centered above capture button
                zoom1xButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                zoom1xButton.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
                
                zoomWideButton.trailingAnchor.constraint(equalTo: zoom1xButton.leadingAnchor, constant: -15),
                zoomWideButton.centerYAnchor.constraint(equalTo: zoom1xButton.centerYAnchor),
                
                zoom2xButton.leadingAnchor.constraint(equalTo: zoom1xButton.trailingAnchor, constant: 15),
                zoom2xButton.centerYAnchor.constraint(equalTo: zoom1xButton.centerYAnchor)
            ])
        }
    }
    
    // This method centers the camera preview in both portrait and landscape
    private func adjustCameraPreviewPosition() {
        guard let picker = imagePickerController else { return }
        
        // Find the camera preview layer
        if let previewView = findCameraPreviewView(in: picker.view) {
            let isLandscape = frame.width > frame.height
            
            // Set a large enough size to ensure the camera preview is visible
            let fullSize = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            
            DispatchQueue.main.async {
                // Make sure preview is properly sized and centered
                previewView.frame = fullSize
                
                // Ensure it's not hidden
                previewView.isHidden = false
                previewView.alpha = 1.0
                
                // Make sure it's centered
                previewView.center = CGPoint(
                    x: self.bounds.width / 2,
                    y: self.bounds.height / 2
                )
            }
        }
    }
    
    // Helper method to find the camera preview view
    private func findCameraPreviewView(in view: UIView) -> UIView? {
        // The camera preview is typically a CALayer added to a view
        // We'll search for it by looking at the view hierarchy
        for subview in view.subviews {
            if NSStringFromClass(type(of: subview)).contains("PLCameraView") ||
                NSStringFromClass(type(of: subview)).contains("PreviewView") {
                return subview
            }
            
            if let found = findCameraPreviewView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - SwiftUI Camera Implementation
struct CameraViewUI: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            SwiftUICameraView(image: $selectedImage)
                .edgesIgnoringSafeArea(.all)
                .onDisappear {
                    // Handle any cleanup needed after the camera view disappears
                }
        }
    }
}

// For previews
struct CameraViewUI_Previews: PreviewProvider {
    @State static var previewImage: UIImage? = nil
    
    static var previews: some View {
        CameraViewUI(selectedImage: $previewImage)
    }
}
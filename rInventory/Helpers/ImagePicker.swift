//
//  ImagePicker.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//
//  A SwiftUI wrapper for PHPickerViewController to select images from the photo library.

import SwiftUI
import PhotosUI
import SwiftyCrop

var swiftyCropConfiguration: SwiftyCropConfiguration {
    SwiftyCropConfiguration(
        maxMagnificationScale: 4.0,
        maskRadius: 130,
        cropImageCircular: false,
        rotateImage: false,
        rotateImageWithButtons: true,
        usesLiquidGlassDesign: usesLiquidGlass,
        zoomSensitivity: 4.0,
        rectAspectRatio: 4/3,
        texts: SwiftyCropConfiguration.Texts(
            cancelButton: "Cancel",
            interactionInstructions: "",
            saveButton: "Save"
        ),
        fonts: SwiftyCropConfiguration.Fonts(
            cancelButton: Font.system(size: 12),
            interactionInstructions: Font.system(size: 14),
            saveButton: Font.system(size: 12)
        ),
        colors: SwiftyCropConfiguration.Colors(
            cancelButton: Color.red,
            interactionInstructions: Color.white,
            saveButton: Color.blue,
            background: Color.gray
        )
    )
}

enum PickerSourceType {
    case photoLibrary
    case camera
}

// MARK: - ImagePicker Wrapper for UIKit
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selection: UIImage?
    let sourceType: PickerSourceType
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        switch sourceType {
        case .photoLibrary:
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        case .camera:
            // Always use our custom landscape-supporting camera implementation
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            picker.allowsEditing = false
            picker.showsCameraControls = false
            
            // Create and set the custom overlay view
            let overlayView = CameraOverlayView(frame: picker.view.frame)
            overlayView.imagePickerController = picker
            picker.cameraOverlayView = overlayView
            
            // Add our appearance delegate to handle view appearance events
            let appearanceDelegate = CameraAppearanceDelegate(overlayView: overlayView)
            context.coordinator.appearanceDelegate = appearanceDelegate
            
            // Use UIKit's appearance events by swizzling the viewDidAppear method
            CameraAppearanceDelegate.swizzleViewDidAppear()
            
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update the overlay view's frame if using custom camera
        if sourceType == .camera,
           let picker = uiViewController as? UIImagePickerController,
           let overlayView = picker.cameraOverlayView as? CameraOverlayView {
            overlayView.frame = picker.view.bounds
            
            // Force layout again
            overlayView.updatePreviewAndLayout()
        }
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        var appearanceDelegate: CameraAppearanceDelegate?
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.selection = image as? UIImage
                }
            }
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.selection = image
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Custom Camera Overlay View
class CameraOverlayView: UIView {
    // UI Elements
    private let captureButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let zoomWideButton = UIButton(type: .system)
    private let zoom1xButton = UIButton(type: .system)
    private let zoom2xButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    
    // Container view for camera preview positioning
    private let cameraContainerView = UIView()
    
    // Properties
    weak var imagePickerController: UIImagePickerController?
    private var currentZoom: CGFloat = 1.0
    private var initialLayoutDone = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        // Make the view transparent for camera content to be visible
        backgroundColor = UIColor.clear
        
        // Add container view for the camera preview
        cameraContainerView.backgroundColor = .clear
        cameraContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cameraContainerView)
        
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
        
        // Force initial layout right away
        setNeedsLayout()
        layoutIfNeeded()
        
        // Schedule another layout pass after a short delay to ensure buttons are properly positioned
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateConstraintsForCurrentOrientation()
            self?.adjustCameraPreviewPosition()
            self?.setNeedsLayout()
            self?.layoutIfNeeded()
        }
    }
    
    private func setupConstraints() {
        // We'll set up adaptive constraints that work in both portrait and landscape
        NSLayoutConstraint.activate([
            // Camera container view takes the full view with padding
            cameraContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cameraContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cameraContainerView.topAnchor.constraint(equalTo: topAnchor),
            cameraContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
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
        
        // We'll update the constraints when orientation changes
        updateConstraintsForCurrentOrientation()
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
        // Actual zoom would be implemented in a real app using AVCaptureDevice
    }
    
    @objc private func setNormalZoom() {
        currentZoom = 1.0
        updateZoomButtonHighlight()
        // Actual zoom would be implemented in a real app using AVCaptureDevice
    }
    
    @objc private func setTelephotoZoom() {
        currentZoom = 2.0
        updateZoomButtonHighlight()
        // Actual zoom would be implemented in a real app using AVCaptureDevice
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
        
        // Always force the initial layout with a correct orientation check
        if !initialLayoutDone {
            initialLayoutDone = true
            updateConstraintsForCurrentOrientation()
            adjustCameraPreviewPosition()
            
            // Schedule another layout pass after the view has been added to the window hierarchy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.updateConstraintsForCurrentOrientation()
                self?.adjustCameraPreviewPosition()
                self?.setNeedsLayout()
                self?.layoutIfNeeded()
            }
        } else {
            updateConstraintsForCurrentOrientation()
            adjustCameraPreviewPosition()
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        // When the view is added to the window hierarchy, force a layout update
        if window != nil {
            updateConstraintsForCurrentOrientation()
            adjustCameraPreviewPosition()
            setNeedsLayout()
            layoutIfNeeded()
        }
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        // When the view is added to a superview, force a layout update
        if superview != nil {
            updateConstraintsForCurrentOrientation()
            adjustCameraPreviewPosition()
            setNeedsLayout()
            layoutIfNeeded()
        }
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
            
            DispatchQueue.main.async {
                if isLandscape {
                    // Landscape adjustments
                    previewView.frame = CGRect(
                        x: 0,
                        y: 0,
                        width: self.bounds.width,
                        height: self.bounds.height
                    )
                } else {
                    // Portrait adjustments - center the preview vertically
                    // This fixes the issue where the camera sticks to the top
                    let previewHeight = previewView.bounds.height
                    let screenHeight = self.bounds.height
                    
                    if previewHeight < screenHeight {
                        // If preview is smaller than screen, center it
                        previewView.frame = CGRect(
                            x: 0,
                            y: (screenHeight - previewHeight) / 2,
                            width: self.bounds.width,
                            height: previewHeight
                        )
                    } else {
                        // Make sure preview takes full width and is centered
                        previewView.frame = CGRect(
                            x: 0,
                            y: 0,
                            width: self.bounds.width,
                            height: self.bounds.height
                        )
                        previewView.center = CGPoint(
                            x: self.bounds.width / 2,
                            y: self.bounds.height / 2
                        )
                    }
                }
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

// MARK: - ImagePicker with Custom Overlay
struct LandscapeCameraImagePicker: UIViewControllerRepresentable {
    @Binding var selection: UIImage?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.showsCameraControls = false
        
        // Create and set the custom overlay view
        let overlayView = CameraOverlayView(frame: picker.view.frame)
        overlayView.imagePickerController = picker
        picker.cameraOverlayView = overlayView
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Update the overlay view's frame if needed
        if let overlayView = uiViewController.cameraOverlayView as? CameraOverlayView {
            overlayView.frame = uiViewController.view.bounds
        }
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LandscapeCameraImagePicker
        
        init(_ parent: LandscapeCameraImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.selection = image
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Convenience Extension for Camera
extension ImagePicker {
    /// A static factory method that creates a camera picker with landscape support
    /// - Parameter selection: Binding to the selected image
    /// - Returns: An ImagePicker configured for camera use with landscape support
    static func camera(selection: Binding<UIImage?>) -> ImagePicker {
        ImagePicker(selection: selection, sourceType: .camera)
    }
    
    /// A static factory method that creates a photo library picker
    /// - Parameter selection: Binding to the selected image
    /// - Returns: An ImagePicker configured for photo library use
    static func photoLibrary(selection: Binding<UIImage?>) -> ImagePicker {
        ImagePicker(selection: selection, sourceType: .photoLibrary)
    }
}

// MARK: - Camera Appearance Delegate
/// A delegate class to handle camera view appearance events
class CameraAppearanceDelegate: NSObject {
    private weak var overlayView: CameraOverlayView?
    
    init(overlayView: CameraOverlayView) {
        self.overlayView = overlayView
        super.init()
    }
    
    /// Swizzles the viewDidAppear method to intercept view appearance events
    static func swizzleViewDidAppear() {
        let originalSelector = #selector(UIViewController.viewDidAppear(_:))
        let swizzledSelector = #selector(CameraAppearanceDelegate.swizzled_viewDidAppear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(CameraAppearanceDelegate.self, swizzledSelector) else { return }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    @objc private func swizzled_viewDidAppear(_ animated: Bool) {
        // Call the original viewDidAppear
        swizzled_viewDidAppear(animated)
        
        // Custom behavior: update the preview and layout
        overlayView?.updatePreviewAndLayout()
    }
}

// MARK: - CameraOverlayView extension
extension CameraOverlayView {
    /// Updates the camera preview and layout
    func updatePreviewAndLayout() {
        guard let picker = imagePickerController else { return }
        
        // Find the camera preview layer
        if let previewView = findCameraPreviewView(in: picker.view) {
            let isLandscape = frame.width > frame.height
            
            DispatchQueue.main.async {
                if isLandscape {
                    // Landscape adjustments
                    previewView.frame = CGRect(
                        x: 0,
                        y: 0,
                        width: self.bounds.width,
                        height: self.bounds.height
                    )
                } else {
                    // Portrait adjustments - center the preview vertically
                    // This fixes the issue where the camera sticks to the top
                    let previewHeight = previewView.bounds.height
                    let screenHeight = self.bounds.height
                    
                    if previewHeight < screenHeight {
                        // If preview is smaller than screen, center it
                        previewView.frame = CGRect(
                            x: 0,
                            y: (screenHeight - previewHeight) / 2,
                            width: self.bounds.width,
                            height: previewHeight
                        )
                    } else {
                        // Make sure preview takes full width and is centered
                        previewView.frame = CGRect(
                            x: 0,
                            y: 0,
                            width: self.bounds.width,
                            height: self.bounds.height
                        )
                        previewView.center = CGPoint(
                            x: self.bounds.width / 2,
                            y: self.bounds.height / 2
                        )
                    }
                }
            }
        }
    }
}

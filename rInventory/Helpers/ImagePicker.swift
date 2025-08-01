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

// MARK: - ImagePicker Wrapper for UIKit
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selection: UIImage?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.selection = image as? UIImage
                }
            }
        }
    }
}

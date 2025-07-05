//
//  ImagePicker.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI
import PhotosUI

// MARK: - ImagePicker Wrapper for UIKit
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var cropImage: ((UIImage, @escaping (UIImage) -> Void) -> Void)? = nil // Optional cropping closure
    
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
                    if let uiImage = image as? UIImage, let crop = self.parent.cropImage {
                        // If cropping is requested, present cropper
                        crop(uiImage) { cropped in
                            self.parent.image = cropped
                        }
                    } else {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

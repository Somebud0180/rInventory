//
//  AsyncItemImage.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/17/25.
//
//  Async image loading component for item images.

import SwiftUI

/// A view that asynchronously loads and displays images from Data.
/// Shows a progress indicator while loading and handles the image conversion on a background thread.
struct AsyncItemImage: View {
    let imageData: Data
    @State private var uiImage: UIImage?
    
    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard uiImage == nil else { return }
        uiImage = UIImage(data: imageData)
    }
}

//
//  AsyncItemImage.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/17/25.
//
//  Async image loading component for item images.

import SwiftUI
import Combine
import ImageIO

/// A view that asynchronously loads and displays images from Data.
/// Shows a progress indicator while loading and handles the image conversion on a background thread.
struct AsyncItemImage: View {
    let imageData: Data
    let maxPixelSize: CGFloat?
    
    init(imageData: Data, maxPixelSize: CGFloat? = nil) {
        self.imageData = imageData
        self.maxPixelSize = maxPixelSize
    }
    
    @State private var uiImage: UIImage?
    @State private var cancellable: AnyCancellable?
    
    // Lightweight, size-aware image cache to avoid re-decoding.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
#if os(watchOS)
        c.totalCostLimit = 12 * 1024 * 1024 // ~12MB cap on watch
        c.countLimit = 150
#else
        c.totalCostLimit = 64 * 1024 * 1024 // ~64MB on iPhone/iPad
        c.countLimit = 400
#endif
        return c
    }()
    
    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancellable?.cancel()
#if os(watchOS)
            // Free the view-held image on watch to keep peak memory low; cache retains a thumbnail.
            uiImage = nil
#endif
        }
    }
    
    private func loadImage() {
        guard uiImage == nil else { return }
        
        // Choose a conservative default max pixel size by platform to keep memory in check.
        // Values are in pixels, not points.
#if os(watchOS)
        let platformDefault: CGFloat = 240 // small thumbnail for watch grids/cards
#else
        let platformDefault: CGFloat = 600 // reasonable thumbnail for phone/iPad lists/cards
#endif
        let targetMaxPixelSize = maxPixelSize ?? platformDefault
        
        // Cache key based on data hash and target size so different sizes don't collide.
        let cacheKey = "\(imageData.hashValue)-\(Int(targetMaxPixelSize))" as NSString
        if let cached = AsyncItemImage.cache.object(forKey: cacheKey) {
            self.uiImage = cached
            return
        }
        
        cancellable = Just(imageData)
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .map { data -> UIImage? in
#if os(watchOS)
                let scale = WKInterfaceDevice.current().screenScale
#else
                let scale = UIScreen.main.scale
#endif
                return downsampledImage(from: data, maxPixelSize: targetMaxPixelSize, scale: scale)
            }
            .receive(on: DispatchQueue.main)
            .sink { image in
                guard let image else { return }
                self.uiImage = image
                let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
                let cost = pixels * 4
                AsyncItemImage.cache.setObject(image, forKey: cacheKey, cost: cost)
            }
    }
}

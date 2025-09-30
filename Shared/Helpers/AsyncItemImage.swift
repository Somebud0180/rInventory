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

actor PrefetchTaskStore {
    private var tasks: [String: Task<Void, Never>] = [:]
    func get(_ key: String) -> Task<Void, Never>? { tasks[key] }
    func set(_ key: String, task: Task<Void, Never>) { tasks[key] = task }
    func remove(_ key: String) { tasks.removeValue(forKey: key) }
    func cancel(_ key: String) { tasks[key]?.cancel(); tasks.removeValue(forKey: key) }
    func cancelAll() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
}

actor InFlightRequestsStore {
    private var requests: [String: AnyCancellable] = [:]
    func get(key: String) -> AnyCancellable? { requests[key] }
    func set(key: String, value: AnyCancellable) { requests[key] = value }
    func remove(key: String) { requests.removeValue(forKey: key) }
    
    func cancelAll() {
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }
}

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
    
    // Lightweight, size-aware in-memory cache to avoid re-decoding.
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
#if os(watchOS)
        c.totalCostLimit = 8 * 1024 * 1024 // ~8MB cap on watch
        c.countLimit = 150
#else
        c.totalCostLimit = 64 * 1024 * 1024 // ~64MB on iPhone/iPad
        c.countLimit = 400
#endif
        return c
    }()
    
    // Keep track of in-flight requests to avoid duplicate processing
    static let inFlightRequests = InFlightRequestsStore()
    
    // Persistent disk cache manager
    static let diskCache = ImageDiskCache()
    
    // Prefetch manager for proactive image loading
    static let prefetcher = ImagePrefetcher()
    
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
            Task {
                await loadImage()
            }
        }
        .onDisappear {
            cancellable?.cancel()
#if os(watchOS)
            // Free the view-held image on watch to keep peak memory low; cache retains a thumbnail.
            uiImage = nil
#endif
        }
    }
    
    private func loadImage() async {
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
        let stringKey = cacheKey as String
        
        // Try to load from in-memory cache first
        if let cached = AsyncItemImage.cache.object(forKey: cacheKey) {
            self.uiImage = cached
            return
        }
        
        // Next, try loading from disk cache
        if let diskCachedImage = AsyncItemImage.diskCache.retrieveImage(forKey: stringKey) {
            self.uiImage = diskCachedImage
            // Store in memory cache for faster subsequent access
            let pixels = Int(diskCachedImage.size.width * diskCachedImage.scale * diskCachedImage.size.height * diskCachedImage.scale)
            let cost = pixels * 4
            AsyncItemImage.cache.setObject(diskCachedImage, forKey: cacheKey, cost: cost)
            return
        }
        
        if let existingRequest = await AsyncItemImage.inFlightRequests.get(key: stringKey) {
            // Subscribe to the existing request rather than creating a new one
            cancellable = existingRequest
            // No explicit .store(in:) is needed; @State holds the cancellable while this view is active
            // We also rely on cache or prefetch mechanism to update uiImage when image arrives
            
            // Since existingRequest is an AnyCancellable, no sink available,
            // So we need to subscribe separately or rely on cache update
            
            // Instead, we'll just return and rely on cache or prefetch mechanism
            return
        }
        
        // If not in cache and no in-flight request, create a new loading task
        let publisher = Just(imageData)
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .map { (data: Data) -> UIImage? in
#if os(watchOS)
                let scale = WKInterfaceDevice.current().screenScale
#else
                let scale = UIScreen.main.scale
#endif
                return downsampledImage(from: data, maxPixelSize: targetMaxPixelSize, scale: scale)
            }
            .receive(on: DispatchQueue.main)
            .share()
        
        // Create a sink subscriber and store it
        let sharedPublisher = publisher.sink { (image: UIImage?) in
            guard let image = image else {
                Task {
                    await AsyncItemImage.inFlightRequests.remove(key: stringKey)
                }
                return
            }
            
            let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
            let cost = pixels * 4
            AsyncItemImage.cache.setObject(image, forKey: cacheKey, cost: cost)
            
            Task {
                await AsyncItemImage.diskCache.storeImage(image, forKey: stringKey)
            }
            
            Task {
                await AsyncItemImage.inFlightRequests.remove(key: stringKey)
            }
        }
        
        await AsyncItemImage.inFlightRequests.set(key: stringKey, value: sharedPublisher)
        
        cancellable = publisher.sink { (image: UIImage?) in
            guard let image = image else { return }
            uiImage = image
        }
    }
}

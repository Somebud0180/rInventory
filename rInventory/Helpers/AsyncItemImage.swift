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
import Foundation
import UniformTypeIdentifiers

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
    static var inFlightRequests = [String: AnyCancellable]()
    static let inFlightLock = NSLock()
    
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
        
        AsyncItemImage.inFlightLock.lock()
        if let existingRequest = AsyncItemImage.inFlightRequests[stringKey] {
            AsyncItemImage.inFlightLock.unlock()
            
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
                AsyncItemImage.inFlightLock.lock()
                AsyncItemImage.inFlightRequests.removeValue(forKey: stringKey)
                AsyncItemImage.inFlightLock.unlock()
                return
            }
            
            let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
            let cost = pixels * 4
            AsyncItemImage.cache.setObject(image, forKey: cacheKey, cost: cost)
            
            Task {
                await AsyncItemImage.diskCache.storeImage(image, forKey: stringKey)
            }
            
            AsyncItemImage.inFlightLock.lock()
            AsyncItemImage.inFlightRequests.removeValue(forKey: stringKey)
            AsyncItemImage.inFlightLock.unlock()
        }
        
        AsyncItemImage.inFlightRequests[stringKey] = sharedPublisher
        AsyncItemImage.inFlightLock.unlock()
        
        cancellable = publisher.sink { (image: UIImage?) in
            guard let image = image else { return }
            uiImage = image
        }
    }
}

/// Disk-based persistent cache manager for processed images
@MainActor
class ImageDiskCache {
    private let cacheDirectoryName = "com.rinventory.imagecache"
    private let fileManager = FileManager.default
    private let cacheSizeLimit: UInt64 = 100 * 1024 * 1024 // 100MB
    private let expirationDays: TimeInterval = 30 // Images expire after 30 days
    
    private var cacheDirectory: URL? {
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheDirectoryName)
    }
    
    // Store these values in memory for access from background threads
    private let cachedDirectoryPath: String
    private let cacheNamespace: String
    
    init() {
        self.cachedDirectoryPath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? ""
        self.cacheNamespace = cacheDirectoryName
        createCacheDirectoryIfNeeded()
        cleanExpiredItems()
    }
    
    private func createCacheDirectoryIfNeeded() {
        guard let cacheDirectory = cacheDirectory else { return }
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create image cache directory: \(error.localizedDescription)")
            }
        }
    }
    
    /// Store image to disk cache
    func storeImage(_ image: UIImage, forKey key: String) async {
        guard let cacheDirectory = cacheDirectory else { return }
        
        // Convert key hash to filename-safe string
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let imageURL = cacheDirectory.appendingPathComponent(safeKey)
        
        do {
            // Check if the image has an alpha channel
            let hasAlpha = image.hasAlphaChannel
            
            // Choose format based on transparency - PNG for images with transparency, JPEG for opaque images
            let data: Data?
            let fileExtension: String
            
            if hasAlpha {
                // Use PNG for images with transparency
                data = image.pngData()
                fileExtension = "png"
            } else {
                // Use JPEG for opaque images (better compression)
                data = image.jpegData(compressionQuality: 0.85)
                fileExtension = "jpg"
            }
            
            guard let imageData = data else {
                print("Failed to encode image data")
                return
            }
            
            // Use an extension to help with content type detection
            let imageURLWithExt = imageURL.appendingPathExtension(fileExtension)
            try imageData.write(to: imageURLWithExt)
            
            // Add metadata for expiration
            let metadataURL = imageURLWithExt.appendingPathExtension("metadata")
            let metadata: [String: Any] = [
                "creationDate": Date().timeIntervalSince1970,
                "size": imageData.count,
                "hasAlpha": hasAlpha
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            try metadataData.write(to: metadataURL)
            
            // Create a safe copy of needed values before detached task
            let cacheDirPath = self.cachedDirectoryPath
            let namespace = self.cacheNamespace
            let limit = self.cacheSizeLimit
            
            // Use detached task with explicitly captured values instead of self
            Task.detached {
                await trimCacheIfNeeded(cacheDirPath: cacheDirPath,
                                        namespace: namespace,
                                        sizeLimit: limit)
            }
        } catch {
            print("Failed to write image to disk cache: \(error.localizedDescription)")
        }
    }
    
    /// Retrieve image from disk cache
    func retrieveImage(forKey key: String) -> UIImage? {
        guard let cacheDirectory = cacheDirectory else { return nil }
        
        // Convert key hash to filename-safe string
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let baseURL = cacheDirectory.appendingPathComponent(safeKey)
        
        // Try the different possible extensions (PNG, JPEG)
        let possibleExtensions = ["png", "jpg"]
        
        for ext in possibleExtensions {
            let imageURL = baseURL.appendingPathExtension(ext)
            
            do {
                if fileManager.fileExists(atPath: imageURL.path) {
                    let data = try Data(contentsOf: imageURL)
                    if let image = UIImage(data: data) {
                        return image
                    }
                }
            } catch {
                print("Failed to read image from disk cache: \(error.localizedDescription)")
            }
        }
        
        // For backward compatibility, try without extension
        do {
            if fileManager.fileExists(atPath: baseURL.path) {
                let data = try Data(contentsOf: baseURL)
                return UIImage(data: data)
            }
        } catch {
            print("Failed to read image from disk cache: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Clean expired items from the cache
    private func cleanExpiredItems() {
        let cacheDirPath = self.cachedDirectoryPath
        let namespace = self.cacheNamespace
        let expirationTime = self.expirationDays
        
        Task.detached {
            await cleanExpiredCacheItems(cacheDirPath: cacheDirPath,
                                         namespace: namespace,
                                         expirationDays: expirationTime)
        }
    }
    
    /// Clear the entire cache
    func clearCache() {
        guard let cacheDirectory = cacheDirectory else { return }
        
        do {
            try fileManager.removeItem(at: cacheDirectory)
            createCacheDirectoryIfNeeded()
        } catch {
            print("Failed to clear image cache: \(error.localizedDescription)")
        }
    }
}

/// A utility class for prefetching images that will likely be needed soon.
/// Use this to preemptively load images for better perceived performance in lists and grids.
class ImagePrefetcher {
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()
    
    /// Start prefetching an image from the given data.
    /// - Parameters:
    ///   - imageData: The image data to prefetch
    ///   - maxPixelSize: Optional maximum pixel size for the image
    func prefetchImage(imageData: Data, maxPixelSize: CGFloat? = nil) {
        // Choose appropriate default max size
#if os(watchOS)
        let platformDefault: CGFloat = 240
#else
        let platformDefault: CGFloat = 600
#endif
        let targetMaxPixelSize = maxPixelSize ?? platformDefault
        
        // Create a cache key for this image+size combination
        let cacheKey = "\(imageData.hashValue)-\(Int(targetMaxPixelSize))"
        
        // Check if already in memory cache - no need to prefetch
        if AsyncItemImage.cache.object(forKey: cacheKey as NSString) != nil {
            return
        }
        
        // Check if there's already a prefetch task for this image
        lock.lock()
        if prefetchTasks[cacheKey] != nil {
            lock.unlock()
            return
        }
        
        // Check if there's an in-flight request - don't duplicate work
        AsyncItemImage.inFlightLock.lock()
        if AsyncItemImage.inFlightRequests[cacheKey] != nil {
            AsyncItemImage.inFlightLock.unlock()
            lock.unlock()
            return
        }
        AsyncItemImage.inFlightLock.unlock()
        
        // Create a new prefetch task with lower priority
        let task = Task(priority: .low) {
            // First check disk cache - if found, just load into memory cache
            if let diskCachedImage = await MainActor.run(body: {
                AsyncItemImage.diskCache.retrieveImage(forKey: cacheKey)
            }) {
                let pixels = Int(diskCachedImage.size.width * diskCachedImage.scale * diskCachedImage.size.height * diskCachedImage.scale)
                let cost = pixels * 4
                AsyncItemImage.cache.setObject(diskCachedImage, forKey: cacheKey as NSString, cost: cost)
                
                // Remove task when done
                lock.lock()
                prefetchTasks.removeValue(forKey: cacheKey)
                lock.unlock()
                return
            }
            
#if os(watchOS)
            let scale = WKInterfaceDevice.current().screenScale
#else
            let scale = UIScreen.main.scale
#endif
            
            guard let processedImage = downsampledImage(from: imageData, maxPixelSize: targetMaxPixelSize, scale: scale) else {
                lock.lock()
                prefetchTasks.removeValue(forKey: cacheKey)
                lock.unlock()
                return
            }
            
            let pixels = Int(processedImage.size.width * processedImage.scale * processedImage.size.height * processedImage.scale)
            let cost = pixels * 4
            AsyncItemImage.cache.setObject(processedImage, forKey: cacheKey as NSString, cost: cost)
            
            await MainActor.run {
                Task {
                    await AsyncItemImage.diskCache.storeImage(processedImage, forKey: cacheKey)
                }
            }
            
            lock.lock()
            prefetchTasks.removeValue(forKey: cacheKey)
            lock.unlock()
        }
        
        prefetchTasks[cacheKey] = task
        lock.unlock()
    }
    
    /// Cancel prefetching for a specific image.
    /// - Parameters:
    ///   - imageData: The image data to stop prefetching
    ///   - maxPixelSize: The maximum pixel size that was specified for prefetching
    func cancelPrefetching(imageData: Data, maxPixelSize: CGFloat? = nil) {
#if os(watchOS)
        let platformDefault: CGFloat = 240
#else
        let platformDefault: CGFloat = 600
#endif
        let targetMaxPixelSize = maxPixelSize ?? platformDefault
        
        let cacheKey = "\(imageData.hashValue)-\(Int(targetMaxPixelSize))"
        
        lock.lock()
        prefetchTasks[cacheKey]?.cancel()
        prefetchTasks.removeValue(forKey: cacheKey)
        lock.unlock()
    }
    
    /// Cancel all ongoing prefetch operations.
    func cancelAllPrefetching() {
        lock.lock()
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        lock.unlock()
    }
}

/// Helper functions that are isolated from the main actor and can run in background

/// Trims cache if it exceeds the size limit
@Sendable
private func trimCacheIfNeeded(cacheDirPath: String, namespace: String, sizeLimit: UInt64) async {
    let fileManager = FileManager.default
    let cacheDirURL = URL(fileURLWithPath: cacheDirPath).appendingPathComponent(namespace)
    
    guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirURL, includingPropertiesForKeys: nil) else { return }
    
    var cacheFiles: [(url: URL, metadata: URL, date: TimeInterval, size: Int)] = []
    
    for fileURL in contents where !fileURL.pathExtension.contains("metadata") {
        let metadataURL = fileURL.appendingPathExtension("metadata")
        
        if fileManager.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                if let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let creationDate = metadata["creationDate"] as? TimeInterval,
                   let size = metadata["size"] as? Int {
                    cacheFiles.append((fileURL, metadataURL, creationDate, size))
                }
            } catch {
                // Skip files with unreadable metadata
            }
        }
    }
    
    let totalSize = cacheFiles.reduce(0) { $0 + UInt64($1.size) }
    
    if totalSize > sizeLimit {
        let sortedFiles = cacheFiles.sorted { $0.date < $1.date }
        
        var currentSize = totalSize
        for file in sortedFiles {
            if currentSize <= sizeLimit {
                break
            }
            
            do {
                try fileManager.removeItem(at: file.url)
                try fileManager.removeItem(at: file.metadata)
                currentSize -= UInt64(file.size)
            } catch {
                print("Failed to remove cache file: \(error.localizedDescription)")
            }
        }
    }
}

/// Cleans expired cache items
@Sendable
private func cleanExpiredCacheItems(cacheDirPath: String, namespace: String, expirationDays: TimeInterval) async {
    let fileManager = FileManager.default
    let cacheDirURL = URL(fileURLWithPath: cacheDirPath).appendingPathComponent(namespace)
    
    guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirURL, includingPropertiesForKeys: nil) else { return }
    
    let now = Date().timeIntervalSince1970
    let expirationInterval = expirationDays * 24 * 60 * 60
    
    for fileURL in contents where fileURL.pathExtension == "metadata" {
        do {
            let data = try Data(contentsOf: fileURL)
            if let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let creationDate = metadata["creationDate"] as? TimeInterval,
               (now - creationDate) > expirationInterval {
                
                let imageURL = fileURL.deletingPathExtension()
                try? fileManager.removeItem(at: imageURL)
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Error processing cache metadata: \(error.localizedDescription)")
        }
    }
}

/// Efficiently creates a downsampled version of an image from the provided data.
/// This approach uses significantly less memory than loading the full image first.
/// - Parameters:
///   - data: The image data to decode
///   - maxPixelSize: The maximum dimension (width or height) of the resulting image
///   - scale: The scale factor to apply (typically the screen scale)
/// - Returns: A downsampled UIImage, or nil if the image couldn't be processed
private func downsampledImage(from data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    
    let uti = CGImageSourceGetType(imageSource) as String? ?? "public.image"
    let sourceHasAlpha = UTType(uti)?.conforms(to: .png) ?? false
    
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldAllowFloat: true
    ]
    
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    
    let aspectRatio = CGFloat(width) / CGFloat(height)
    let targetSize: CGSize
    
    if width > height {
        let targetWidth = min(CGFloat(width), maxPixelSize)
        targetSize = CGSize(width: targetWidth, height: targetWidth / aspectRatio)
    } else {
        let targetHeight = min(CGFloat(height), maxPixelSize)
        targetSize = CGSize(width: targetHeight * aspectRatio, height: targetHeight)
    }
    
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height),
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true
    ]
    
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
        return nil
    }
    
#if !os(watchOS)
    if sourceHasAlpha {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: thumbnail.width, height: thumbnail.height), format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: thumbnail, scale: scale, orientation: .up).draw(in: CGRect(origin: .zero, size: CGSize(width: thumbnail.width, height: thumbnail.height)))
        }
        return image
    }
#endif
    
    return UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
}

extension UIImage {
    /// Check if the image has an alpha channel (transparency)
    var hasAlphaChannel: Bool {
        guard let cgImage = self.cgImage else { return false }
        
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst || alphaInfo == .last || alphaInfo == .first
    }
}

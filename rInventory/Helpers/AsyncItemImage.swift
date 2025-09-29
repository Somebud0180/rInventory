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
    
    // Persistent disk cache manager
    private static let diskCache = ImageDiskCache()
    
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
        
        // Try to load from in-memory cache first
        if let cached = AsyncItemImage.cache.object(forKey: cacheKey) {
            self.uiImage = cached
            return
        }
        
        // Next, try loading from disk cache
        if let diskCachedImage = AsyncItemImage.diskCache.retrieveImage(forKey: cacheKey as String) {
            self.uiImage = diskCachedImage
            // Store in memory cache for faster subsequent access
            let pixels = Int(diskCachedImage.size.width * diskCachedImage.scale * diskCachedImage.size.height * diskCachedImage.scale)
            let cost = pixels * 4
            AsyncItemImage.cache.setObject(diskCachedImage, forKey: cacheKey, cost: cost)
            return
        }
        
        // If not in cache, process the image
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
                
                // Store in memory cache
                AsyncItemImage.cache.setObject(image, forKey: cacheKey, cost: cost)
                
                // Also store in disk cache
                Task {
                    await AsyncItemImage.diskCache.storeImage(image, forKey: cacheKey as String)
                }
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
            if let data = image.pngData() {
                try data.write(to: imageURL)
                
                // Add metadata for expiration
                let metadataURL = imageURL.appendingPathExtension("metadata")
                let metadata: [String: Any] = [
                    "creationDate": Date().timeIntervalSince1970,
                    "size": data.count
                ]
                try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
                
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
        let imageURL = cacheDirectory.appendingPathComponent(safeKey)
        
        do {
            if fileManager.fileExists(atPath: imageURL.path) {
                let data = try Data(contentsOf: imageURL)
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

// Helper functions that are isolated from the main actor and can run in background

/// Trims cache if it exceeds the size limit
@Sendable
private func trimCacheIfNeeded(cacheDirPath: String, namespace: String, sizeLimit: UInt64) async {
    let fileManager = FileManager.default
    let cacheDirURL = URL(fileURLWithPath: cacheDirPath).appendingPathComponent(namespace)
    
    guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirURL, includingPropertiesForKeys: nil) else { return }
    
    var cacheFiles: [(url: URL, metadata: URL, date: TimeInterval, size: Int)] = []
    
    // Collect files with their metadata
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
    
    // Calculate total size
    let totalSize = cacheFiles.reduce(0) { $0 + UInt64($1.size) }
    
    // If exceeding size limit, remove oldest files first until under limit
    if totalSize > sizeLimit {
        // Sort by date (oldest first)
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
    let expirationInterval = expirationDays * 24 * 60 * 60 // days to seconds
    
    for fileURL in contents where fileURL.pathExtension == "metadata" {
        do {
            let data = try Data(contentsOf: fileURL)
            if let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let creationDate = metadata["creationDate"] as? TimeInterval,
               (now - creationDate) > expirationInterval {
                
                // Remove the image file
                let imageURL = fileURL.deletingPathExtension()
                try? fileManager.removeItem(at: imageURL)
                
                // Remove the metadata file
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
    // Create an image source
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    
    // Get original dimensions to calculate aspect ratio
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    
    // Calculate target size while maintaining aspect ratio
    let aspectRatio = CGFloat(width) / CGFloat(height)
    let targetSize: CGSize
    
    if width > height {
        let targetWidth = min(CGFloat(width), maxPixelSize)
        targetSize = CGSize(width: targetWidth, height: targetWidth / aspectRatio)
    } else {
        let targetHeight = min(CGFloat(height), maxPixelSize)
        targetSize = CGSize(width: targetHeight * aspectRatio, height: targetHeight)
    }
    
    // Create thumbnail options specifying the target size
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height)
    ]
    
    // Create the thumbnail
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
        return nil
    }
    
    return UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
}

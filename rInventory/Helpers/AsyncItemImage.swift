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
class ImageDiskCache {
    private let cacheDirectoryName = "com.rinventory.imagecache"
    private let fileManager = FileManager.default
    private let cacheSizeLimit: UInt64 = 100 * 1024 * 1024 // 100MB
    private let expirationDays: TimeInterval = 30 // Images expire after 30 days
    
    private var cacheDirectory: URL? {
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheDirectoryName)
    }
    
    init() {
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
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        // Convert key hash to filename-safe string
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let imageURL = cacheDirectory.appendingPathComponent(safeKey)
        
        do {
            if let data = image.jpegData(compressionQuality: 0.8) {
                try data.write(to: imageURL)
                
                // Add metadata for expiration
                let metadataURL = imageURL.appendingPathExtension("metadata")
                let metadata: [String: Any] = [
                    "creationDate": Date().timeIntervalSince1970,
                    "size": data.count
                ]
                try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
                
                // Check if we need to trim the cache
                Task.detached { [weak self] in
                    self?.trimCacheIfNeeded()
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
        Task.detached { [weak self] in
            guard let self = self,
                  let cacheDirectory = self.cacheDirectory,
                  let contents = try? self.fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
            
            let now = Date().timeIntervalSince1970
            let expirationInterval = self.expirationDays * 24 * 60 * 60 // days to seconds
            
            for fileURL in contents where fileURL.pathExtension == "metadata" {
                do {
                    let data = try Data(contentsOf: fileURL)
                    if let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let creationDate = metadata["creationDate"] as? TimeInterval,
                       (now - creationDate) > expirationInterval {
                        
                        // Remove the image file
                        let imageURL = fileURL.deletingPathExtension()
                        try? self.fileManager.removeItem(at: imageURL)
                        
                        // Remove the metadata file
                        try? self.fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    print("Error processing cache metadata: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Trim the cache if it exceeds the size limit
    private func trimCacheIfNeeded() {
        guard let cacheDirectory = cacheDirectory,
              let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        
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
        if totalSize > cacheSizeLimit {
            // Sort by date (oldest first)
            let sortedFiles = cacheFiles.sorted { $0.date < $1.date }
            
            var currentSize = totalSize
            for file in sortedFiles {
                if currentSize <= cacheSizeLimit {
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

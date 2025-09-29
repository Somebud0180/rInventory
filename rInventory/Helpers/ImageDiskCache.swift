//
//  ImageDiskCache.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/29/25.
//
//  Contains a disk-based cache manager for processed images with expiration and size limit.

import SwiftUI

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

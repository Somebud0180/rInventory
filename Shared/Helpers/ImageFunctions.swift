//
//  ImageFunctions.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/29/25.
//
//  Contains helper functions for image caching, trimming, and downsampling.

import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers

/// Trims cache if it exceeds the size limit
@Sendable
func trimCacheIfNeeded(cacheDirPath: String, namespace: String, sizeLimit: UInt64) async {
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
func cleanExpiredCacheItems(cacheDirPath: String, namespace: String, expirationDays: TimeInterval) async {
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
func downsampledImage(from data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
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

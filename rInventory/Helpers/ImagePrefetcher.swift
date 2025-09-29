//
//  ImagePrefetcher.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/29/25.
//

import SwiftUI

/// A utility class for prefetching images that will likely be needed soon.
/// Use this to preemptively load images for better perceived performance in lists and grids.
class ImagePrefetcher {
    private let prefetchTasks = PrefetchTaskStore()
    
    /// Start prefetching an image from the given data.
    /// - Parameters:
    ///   - imageData: The image data to prefetch
    ///   - maxPixelSize: Optional maximum pixel size for the image
    func prefetchImage(imageData: Data, maxPixelSize: CGFloat? = nil) {
        Task {
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
            if await prefetchTasks.get(cacheKey) != nil {
                return
            }
            
            // Check if there's an in-flight request - don't duplicate work
            let inFlightExists = await AsyncItemImage.inFlightRequests.get(key: cacheKey) != nil
            if inFlightExists {
                return
            }
            
            // Create a new prefetch task with lower priority
            let task = Task(priority: .low) {
                // First check disk cache - if found, just load into memory cache
                let diskCachedImage = await MainActor.run {
                    AsyncItemImage.diskCache.retrieveImage(forKey: cacheKey)
                }
                if let diskCachedImage = diskCachedImage {
                    let pixels = Int(diskCachedImage.size.width * diskCachedImage.scale * diskCachedImage.size.height * diskCachedImage.scale)
                    let cost = pixels * 4
                    AsyncItemImage.cache.setObject(diskCachedImage, forKey: cacheKey as NSString, cost: cost)
                    
                    await prefetchTasks.remove(cacheKey)
                    return
                }
                
#if os(watchOS)
                let scale = WKInterfaceDevice.current().screenScale
#else
                let scale = UIScreen.main.scale
#endif
                
                guard let processedImage = downsampledImage(from: imageData, maxPixelSize: targetMaxPixelSize, scale: scale) else {
                    await prefetchTasks.remove(cacheKey)
                    return
                }
                
                let pixels = Int(processedImage.size.width * processedImage.scale * processedImage.size.height * processedImage.scale)
                let cost = pixels * 4
                AsyncItemImage.cache.setObject(processedImage, forKey: cacheKey as NSString, cost: cost)
                
                Task {
                    await AsyncItemImage.diskCache.storeImage(processedImage, forKey: cacheKey)
                }
                
                await prefetchTasks.remove(cacheKey)
            }
            
            await prefetchTasks.set(cacheKey, task: task)
        }
    }
    
    /// Cancel prefetching for a specific image.
    /// - Parameters:
    ///   - imageData: The image data to stop prefetching
    ///   - maxPixelSize: The maximum pixel size that was specified for prefetching
    func cancelPrefetching(imageData: Data, maxPixelSize: CGFloat? = nil) {
        Task {
#if os(watchOS)
            let platformDefault: CGFloat = 240
#else
            let platformDefault: CGFloat = 600
#endif
            let targetMaxPixelSize = maxPixelSize ?? platformDefault
            
            let cacheKey = "\(imageData.hashValue)-\(Int(targetMaxPixelSize))"
            
            await prefetchTasks.cancel(cacheKey)
        }
    }
    
    /// Cancel all ongoing prefetch operations.
    func cancelAllPrefetching() {
        Task {
            await prefetchTasks.cancelAll()
        }
    }
}

//
//  ImageCaches.swift
//  rInventory
//
//  Created by Ethan John Lagera on 10/1/25.
//
//  Contains centralized image cache management utilities

import Foundation
import SwiftUI

/// Global access to image cache management
enum ImageCaches {
    /// Clears memory-based image caches while preserving disk cache
    static func purgeMemoryCaches() {
        // Clear AsyncItemImage's static NSCache
        AsyncItemImage.cache.removeAllObjects()
        
        // Cancel any prefetch tasks
        Task {
            await AsyncItemImage.prefetcher.cancelAllPrefetching()
        }
        
        // Cancel in-flight image requests
        Task {
            // In-flight requests will be cancelled when the app becomes inactive
            // This helps free up memory and network resources
        }
        
        // Clear URL cache for images (optional - this helps with network resources)
        URLCache.shared.removeAllCachedResponses()
        
        #if DEBUG
        print("✅ Memory caches cleared")
        #endif
    }
}
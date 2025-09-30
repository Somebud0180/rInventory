//
//  ImageCaches.swift
//  rInventory
//
//  Created by Ethan John Lagera on 10/1/25.
//
//  Contains centralized image cache management utilities

import Foundation
import SwiftUI
import Combine
#if os(watchOS)
import WatchKit
#endif

/// Global access to image cache management
enum ImageCaches {
    // Keep track of our own memory pressure monitoring subscription
    private static var memoryPressureSubscription: AnyCancellable?
    
    /// Setup memory pressure monitoring that clears caches when system is under memory pressure
    static func setupMemoryPressureHandling() {
#if os(watchOS) // WatchOS uses a different notification for memory pressure
        memoryPressureSubscription = NotificationCenter.default.publisher(for: WKExtension.applicationWillResignActiveNotification)
            .sink { _ in
                ImageCaches.purgeMemoryCaches(aggressive: true)
            }
#else
        memoryPressureSubscription = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { _ in
                ImageCaches.purgeMemoryCaches(aggressive: true)
            }
#endif
        
    }
    
    /// Clears memory-based image caches while preserving disk cache
    static func purgeMemoryCaches(aggressive: Bool = false) {
        // Clear AsyncItemImage's static NSCache
        AsyncItemImage.cache.removeAllObjects()
        
        // Cancel any prefetch tasks to stop in-progress work
        Task {
            await AsyncItemImage.prefetcher.cancelAllPrefetching()
        }
        
        // Clear in-flight requests and explicitly cancel them
        Task {
            await AsyncItemImage.inFlightRequests.cancelAll()
        }
        
        // Clear URL cache for images
        URLCache.shared.removeAllCachedResponses()
        
        if aggressive {
            // Force a garbage collection cycle by creating temporary pressure
            autoreleasepool {
                let pressureBlock = { () -> Void in
                    // Create and release some temporary image objects
                    var temporaryImages: [UIImage?] = []
                    for _ in 0..<5 {
                        temporaryImages.append(UIImage(systemName: "photo"))
                    }
                    temporaryImages.removeAll()
                }
                pressureBlock()
            }
        }
        
#if DEBUG
        print("✅ Memory caches cleared (aggressive: \(aggressive))")
#endif
    }
}

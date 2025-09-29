// filepath: /Users/ethanlagera/Documents/XCode/rInventory/rInventory/Helpers/ItemCardPrefetchHelper.swift
//
//  ItemCardPrefetchHelper.swift
//  rInventory
//
//  Created on 9/29/25.
//
//  Helper for prefetching item card images to improve scrolling performance.

import Foundation
import SwiftUI

/// Helper for managing prefetching of item images
struct ItemImagePrefetcher {
    /// Start prefetching images for a collection of items that will appear soon
    static func prefetchImagesForItems<T: Identifiable>(_ items: [T], imageDataProvider: (T) -> Data?) {
        for item in items {
            if let imageData = imageDataProvider(item) {
                AsyncItemImage.prefetcher.prefetchImage(imageData: imageData)
            }
        }
    }
    
    /// Cancel prefetching for items that are no longer needed
    static func cancelPrefetchingForItems<T: Identifiable>(_ items: [T], imageDataProvider: (T) -> Data?) {
        for item in items {
            if let imageData = imageDataProvider(item) {
                AsyncItemImage.prefetcher.cancelPrefetching(imageData: imageData)
            }
        }
    }
    
    /// Cancel all prefetch operations - typically called when leaving a view
    static func cancelAllPrefetching() {
        AsyncItemImage.prefetcher.cancelAllPrefetching()
    }
}

// MARK: - Prefetching modifiers for SwiftUI views

extension View {
    /// Apply this modifier to a List or ScrollView to enable image prefetching for items
    func prefetchImages<T: Identifiable & Equatable>(
        for visibleItems: [T],
        upcomingItems: [T],
        imageDataProvider: @escaping (T) -> Data?
    ) -> some View {
        self.onAppear {
            // Prefetch both visible and upcoming items on initial appearance
            ItemImagePrefetcher.prefetchImagesForItems(visibleItems + upcomingItems, imageDataProvider: imageDataProvider)
        }
        .onDisappear {
            ItemImagePrefetcher.cancelAllPrefetching()
        }
        .onChange(of: visibleItems) { _, newVisibleItems in
            // When visible items change, prefetch the upcoming items
            ItemImagePrefetcher.prefetchImagesForItems(upcomingItems, imageDataProvider: imageDataProvider)
            
            // Create a set of all IDs that are either visible or upcoming
            let visibleAndUpcomingIDs = Set((newVisibleItems + upcomingItems).map { $0.id })
            
            // Determine which previously prefetched items are no longer needed
            let itemsToCancel = visibleItems.filter { !visibleAndUpcomingIDs.contains($0.id) }
            ItemImagePrefetcher.cancelPrefetchingForItems(itemsToCancel, imageDataProvider: imageDataProvider)
        }
    }
    
    /// Simple prefetch modifier that just cancels all prefetch operations when the view disappears
    func cancelPrefetchingOnDisappear() -> some View {
        self.onDisappear {
            ItemImagePrefetcher.cancelAllPrefetching()
        }
    }
}

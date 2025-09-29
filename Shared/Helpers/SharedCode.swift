//
//  SharedCode.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/28/25.
//
//  Contains other uncategorized shared code used in the app.

import SwiftUI
import Combine
import ImageIO

// MARK: - View and Color Code
extension View {
    /// Applies a modifier to the view conditionally.
    /// - Parameters:
    ///  - condition: The condition to evaluate.
    ///  - transform: The modifier to apply if the condition is true.
    ///  - Returns: Either the original view or the modified view based on the condition.
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension Color {
    /// Returns the relative luminance of this color, from 0 (black) to 1 (white).
    func luminance() -> Double {
        // Convert the color to UIColor/NSColor and extract components
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
#else
        let nsColor = NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
#endif
        
        // Calculate luminance (perceptual brightness)
        func channel(_ c: CGFloat) -> Double {
            let c = Double(c)
            return (c <= 0.03928) ? (c/12.92) : pow((c+0.055)/1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
    
    /// Determines if the color is considered "white" based on its luminance.
    func isColorWhite(sensitivity: CGFloat = 0.75) -> Bool {
        return self.luminance() >= sensitivity
    }
}

// MARK: - Image Code
extension UIImage {
    /// Check if the image has an alpha channel (transparency)
    var hasAlphaChannel: Bool {
        guard let cgImage = self.cgImage else { return false }
        
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst || alphaInfo == .last || alphaInfo == .first
    }
}

extension AsyncItemImage {
    /// Static method to check if an image has actual transparency.
    /// - Parameter data: The image data to check.
    /// - Returns: `true` if the image has actual transparency, otherwise `false`.
    static func hasAlphaChannel(in data: Data) -> Bool {
        // Create an image source from the image data
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return false
        }
        
        // First check if the image format even supports alpha
        let alphaInfo = cgImage.alphaInfo
        let hasAlphaFormat = alphaInfo != CGImageAlphaInfo.none &&
        alphaInfo != CGImageAlphaInfo.noneSkipLast &&
        alphaInfo != CGImageAlphaInfo.noneSkipFirst
        
        // If the format doesn't support alpha, return false immediately
        if !hasAlphaFormat {
            return false
        }
        
        // Check for actual transparency in the image
        // Get width and height of the image
        let width = cgImage.width
        let height = cgImage.height
        
        // Create a context for scanning the pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // Allocate memory for the pixels
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(data: &pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        
        // Draw the image into the context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Sample a reasonable number of pixels to check for transparency
        // We don't need to check every pixel, just sample across the image
        let samplingCount = min(width * height, 240) // Limit to reasonable number of pixels
        let samplingStep = max(1, (width * height) / samplingCount)
        
        for i in stride(from: 3, to: pixelData.count, by: samplingStep * 4) {
            // Alpha component is the 4th byte (index 3, 7, 11, etc.)
            if pixelData[i] < 255 {
                // Found a transparent or semi-transparent pixel
                return true
            }
        }
        
        // No transparent pixels found in our sample
        return false
    }
}

/// Calculates which items are likely to appear next during scrolling
func calculateUpcomingItems(_ items: [Item], visibleItemIDs: Set<Item.ID>, prefetchBatchSize: Int) -> [Item] {
    // Find the highest (furthest down) visible item index
    if let maxVisibleIndex = items.indices.filter({ visibleItemIDs.contains(items[$0].id) }).max() {
        // Calculate the next batch of items that will appear during scrolling
        let startIndex = min(maxVisibleIndex + 1, items.count - 1)
        let endIndex = min(startIndex + prefetchBatchSize, items.count - 1)
        
        // If we have a valid range, return those upcoming items
        if startIndex <= endIndex {
            return Array(items[startIndex...endIndex])
        }
    }
    
    // If we have no visible items yet (initial load) or all items are already visible,
    // return the first few items or an empty array
    if items.isEmpty {
        return []
    }
    return Array(items.prefix(min(prefetchBatchSize, items.count)))
}

/// Optimizes PNG image data by re-encoding it with lossless compression.
/// - Parameter data: The original PNG image data.
/// - Returns: The optimized PNG image data, or `nil` if optimization fails.
func optimizePNGData(_ data: Data) -> Data? {
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
          let imageType = CGImageSourceGetType(imageSource) else {
        return nil
    }
    
    let options: [NSString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 1.0, // Ensure lossless compression
        kCGImagePropertyPNGCompressionFilter: 0 // Use the fastest filter for PNG
    ]
    
    let outputData = NSMutableData()
    guard let imageDestination = CGImageDestinationCreateWithData(outputData, imageType, 1, nil) else {
        return nil
    }
    
    CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, options as CFDictionary)
    guard CGImageDestinationFinalize(imageDestination) else {
        return nil
    }
    
    return outputData as Data
}

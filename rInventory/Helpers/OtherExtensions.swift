//
//  OtherExtensions.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/28/25.
//
//  Contains other uncategorized extensions used in the app.

import SwiftUI
import Combine
import ImageIO

#if os(iOS)
/// Extension used in iOS only.
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

extension AsyncItemImage {
    /// Checks if the image has an alpha channel with actual transparency.
    /// - Returns: `true` if the image has actual transparency, otherwise `false`.
    func hasAlphaChannel() -> Bool {
        return AsyncItemImage.hasAlphaChannel(in: imageData)
    }
    
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
        let samplingCount = min(width * height, 10000) // Limit to reasonable number of pixels
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
#endif // os(iOS)


/// Efficiently creates a downsampled version of an image from the provided data.
/// This approach uses significantly less memory than loading the full image first.
/// - Parameters:
///   - data: The image data to decode
///   - maxPixelSize: The maximum dimension (width or height) of the resulting image
///   - scale: The scale factor to apply (typically the screen scale)
/// - Returns: A downsampled UIImage, or nil if the image couldn't be processed
func downsampledImage(from data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
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

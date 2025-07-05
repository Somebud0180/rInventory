//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Int? = 1
    var location: Location?
    var category: Category?
    var imageData: Data?
    var symbol: String?
    var symbolColorData: Data?
    var sortOrder: Int = 0
    var modifiedDate: Date = Date()
    
    init(_ id: UUID = UUID(), name: String, quantity: Int? = 1, location: Location? = nil, category: Category? = nil, imageData: Data? = nil, symbol: String? = nil, symbolColor: Color? = .accentColor, sortOrder: Int = 0, modifiedDate: Date = Date()) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.location = location
        self.category = category
        self.imageData = imageData
        self.symbol = symbol
        self.symbolColorData = symbolColor?.rgbaData
        self.sortOrder = sortOrder
        self.modifiedDate = modifiedDate
    }
    
    var symbolColor: Color {
        get {
            guard let symbolColorData else { return .accentColor }
            return Color(rgbaData: symbolColorData) ?? .accentColor
        }
        set {
            symbolColorData = newValue.rgbaData
        }
    }
}

@Model
final class Category {
    var name: String = ""
    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var items: [Item]?
    
    init(name: String) {
        self.name = name
    }
}

@Model
final class Location {
    var name: String = ""
    var colorData: Data?
    @Relationship(deleteRule: .nullify, inverse: \Item.location)
    var items: [Item]?
    
    init(name: String, color: Color? = .primary) {
        self.name = name
        self.colorData = color?.rgbaData
    }
    
    var color: Color {
        get {
            guard let colorData else { return .white }
            return Color(rgbaData: colorData) ?? .white
        }
        set {
            colorData = newValue.rgbaData
        }
    }
}

extension Item {
    func update(
        name: String? = nil,
        quantity: Int? = nil,
        location: Location? = nil,
        category: Category? = nil,
        imageData: Data? = nil,
        symbol: String? = nil,
        symbolColor: Color? = nil
    ) {
        if let name = name { self.name = name }
        if let quantity = quantity { self.quantity = quantity }
        if let location = location { self.location = location }
        if let category = category { self.category = category }
        if let imageData = imageData { self.imageData = imageData }
        if let symbol = symbol { self.symbol = symbol }
        if let symbolColor = symbolColor { self.symbolColor = symbolColor }
        self.modifiedDate = Date()
    }
    
    /// Removes orphaned categories and locations that have no items
    static func cleanupOrphanedEntities(in context: ModelContext) {
        // Clean up categories with no items
        let categoryDescriptor = FetchDescriptor<Category>()
        if let categories = try? context.fetch(categoryDescriptor) {
            for category in categories {
                if category.items?.isEmpty ?? true {
                    context.delete(category)
                }
            }
        }
        
        // Clean up locations with no items
        let locationDescriptor = FetchDescriptor<Location>()
        if let locations = try? context.fetch(locationDescriptor) {
            for location in locations {
                if location.items?.isEmpty ?? true {
                    context.delete(location)
                }
            }
        }
        
        // Save changes
        try? context.save()
    }
}

extension Category {
    /// Deletes this category if it has no items
    func deleteIfEmpty(from context: ModelContext) {
        if items?.isEmpty ?? true {
            context.delete(self)
        }
    }
}

extension Location {
    /// Deletes this location if it has no items
    func deleteIfEmpty(from context: ModelContext) {
        if items?.isEmpty ?? true {
            context.delete(self)
        }
    }
}

extension Color {
    /// Returns the RGBA components packed into Data (8 bits per channel)
    var rgbaData: Data? {
        let components = self.rgbaComponents
        let r = UInt8((components.0 * 255).rounded())
        let g = UInt8((components.1 * 255).rounded())
        let b = UInt8((components.2 * 255).rounded())
        let a = UInt8((components.3 * 255).rounded())
        return Data([r, g, b, a])
    }
    /// Initializes a Color from RGBA-packed Data
    init?(rgbaData data: Data) {
        guard data.count == 4 else { return nil }
        let r = Double(data[0]) / 255.0
        let g = Double(data[1]) / 255.0
        let b = Double(data[2]) / 255.0
        let a = Double(data[3]) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    /// Returns (red, green, blue, alpha) components as Double (0...1)
    var rgbaComponents: (Double, Double, Double, Double) {
#if os(macOS)
        typealias NativeColor = NSColor
#else
        typealias NativeColor = UIColor
#endif
        guard let cgColor = self.cgColor else { return (1, 1, 1, 1) }
        let native = NativeColor(cgColor: cgColor)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

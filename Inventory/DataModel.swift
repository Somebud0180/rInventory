//
//  DataModel.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Contains the data model definitions for Item, Category, and Location. As well as utility methods for managing these models.

import Foundation
import SwiftData
import SwiftUI

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Int = 0
    var location: Location?
    var category: Category?
    var imageData: Data?
    var symbol: String?
    var symbolColorData: Data?
    var sortOrder: Int = 0
    var modifiedDate: Date = Date()
    
    init(_ id: UUID = UUID(), name: String, quantity: Int, location: Location? = nil, category: Category? = nil, imageData: Data? = nil, symbol: String? = nil, symbolColor: Color? = .accentColor, sortOrder: Int = 0, modifiedDate: Date = Date()) {
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
    /// Creates and inserts a new Item into the context, including creating or finding location/category as needed, and sets proper sort order.
    static func saveItem(
        name: String,
        quantity: Int,
        locationName: String,
        locationColor: Color,
        categoryName: String,
        background: GridCardBackground,
        symbolColor: Color,
        items: [Item],
        locations: [Location],
        categories: [Category],
        context: ModelContext
    ) {
        // Helper to find or create location
        func findOrCreateLocation(locationName: String, locationColor: Color) -> Location {
            if let existing = locations.first(where: { $0.name == locationName }) {
                return existing
            } else {
                let newLoc = Location(name: locationName, color: locationColor)
                context.insert(newLoc)
                return newLoc
            }
        }
        // Helper to find or create category
        func findOrCreateCategory(categoryName: String) -> Category? {
            guard !categoryName.isEmpty else { return nil }
            if let existing = categories.first(where: { $0.name == categoryName }) {
                return existing
            } else {
                let newCat = Category(name: categoryName)
                context.insert(newCat)
                return newCat
            }
        }
        // Extract background
        let (imageData, symbol, usedSymbolColor): (Data?, String?, Color?) = {
            switch background {
            case let .symbol(symbol):
                return (nil, symbol, symbolColor)
            case let .image(data):
                return (data, nil, nil)
            }
        }()
        let sortOrder = (items.map { $0.sortOrder }.max() ?? -1) + 1
        let item = Item(
            name: name,
            quantity: max(quantity, 0),
            location: findOrCreateLocation(locationName: locationName, locationColor: locationColor),
            category: findOrCreateCategory(categoryName: categoryName),
            imageData: imageData,
            symbol: symbol,
            symbolColor: usedSymbolColor,
            sortOrder: sortOrder
        )
        context.insert(item)
        try? context.save()
    }

    /// Updates this Item and persists, cleaning up orphans.
    func updateItem(
        name: String,
        quantity: Int,
        location: Location?,
        category: Category?,
        background: GridCardBackground,
        symbolColor: Color?,
        context: ModelContext
    ) {
        let oldLocation = self.location
        let oldCategory = self.category
        var updateImageData: Data? = nil
        var updateSymbol: String? = nil
        var updateSymbolColor: Color? = nil
        switch background {
        case let .symbol(symbol):
            updateSymbol = symbol
            updateSymbolColor = symbolColor ?? .accentColor
            updateImageData = nil
        case let .image(data):
            updateImageData = data
            updateSymbol = nil
            updateSymbolColor = nil
        }
        
        // Save changes
        self.name = name
        self.location = location
        self.category = category
        self.imageData = updateImageData
        self.symbol = updateSymbol
        self.symbolColor = updateSymbolColor ?? .accentColor
        self.modifiedDate = Date()
        
        oldLocation?.deleteIfEmpty(from: context)
        oldCategory?.deleteIfEmpty(from: context)
        try? context.save()
    }

    /// Deletes this Item, handles orphaned category/location, and cascades sortOrder.
    func deleteItem(
        context: ModelContext,
        items: [Item]
    ) {
        let oldLocation = self.location
        let oldCategory = self.category
        let deletedOrder = self.sortOrder
        context.delete(self)
        oldLocation?.deleteIfEmpty(from: context)
        oldCategory?.deleteIfEmpty(from: context)
        // Cascade sortOrder
        let itemsToUpdate = items.filter { $0.sortOrder > deletedOrder }
        for otherItem in itemsToUpdate {
            otherItem.sortOrder -= 1
        }
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

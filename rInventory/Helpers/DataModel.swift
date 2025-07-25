//
//  DataModel.swift
//  rInventory
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
    var itemCreationDate: Date = Date()
    
    init(_ id: UUID = UUID(), name: String, quantity: Int, location: Location? = nil, category: Category? = nil, imageData: Data? = nil, symbol: String? = nil, symbolColor: Color? = .accentColor, sortOrder: Int = 0, modifiedDate: Date = Date(), itemCreationDate: Date = Date()) {
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
        self.itemCreationDate = itemCreationDate
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
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0 // Used for sorting the location rows
    var displayInRow: Bool = true // Whether to show this location in the main list
    var colorData: Data?
    @Relationship(deleteRule: .nullify, inverse: \Item.location)
    var items: [Item]?
    
    init(_ id: UUID = UUID(), name: String, sortOrder: Int = 0, displayInRow: Bool = true, color: Color = Color.white, items: [Item]? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.colorData = color.rgbaData
        self.displayInRow = displayInRow
        self.items = items
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

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0 // Used for sorting the category rows
    var displayInRow: Bool = true // Whether to show this category in the main list
    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var items: [Item]?
    
    init(_ id: UUID = UUID(), name: String, sortOrder: Int = 0, displayInRow: Bool = true, items: [Item]? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.displayInRow = displayInRow
        self.items = items
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
        background: ItemCardBackground,
        symbolColor: Color,
        context: ModelContext
    ) {
        // Fetch existing items
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        
        // Find or create location and category
        let location = !locationName.isEmpty ? Location.findOrCreate(name: locationName, color: locationColor, context: context) : nil
        let category = !categoryName.isEmpty ? Category.findOrCreate(name: categoryName, context: context) : nil
        
        // Extract background
        let (imageData, symbol, usedSymbolColor): (Data?, String?, Color?) = {
            switch background {
            case let .symbol(symbol):
                return (nil, symbol, symbolColor)
            case let .image(data):
                return (data, nil, nil)
            }
        }()
        
        // Determine the next sort order
        let sortOrder = (items.map { $0.sortOrder }.max() ?? -1) + 1
        
        let item = Item(
            name: name,
            quantity: max(quantity, 0),
            location: location,
            category: category,
            imageData: imageData,
            symbol: symbol,
            symbolColor: usedSymbolColor,
            sortOrder: sortOrder,
            modifiedDate: Date(),
            itemCreationDate: Date()
        )
        context.insert(item)
        try? context.save()
    }
    
    /// Updates this Item and persists, cleaning up orphans.
    func updateItem(
        name: String? = nil,
        quantity: Int? = nil,
        locationName: String? = nil,
        locationColor: Color? = nil,
        categoryName: String? = nil,
        background: ItemCardBackground? = nil,
        symbolColor: Color? = nil,
        context: ModelContext
    ) async {
        // Find or create Location
        var newLocation: Location?
        if let locationName = locationName, !locationName.isEmpty, let locationColor = locationColor {
            let trimmedLocationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            newLocation = !trimmedLocationName.isEmpty ? Location.findOrCreate(name: trimmedLocationName, color: locationColor, context: context) : nil
        }
        
        // Find or create Category
        var newCategory: Category?
        if let categoryName = categoryName, !categoryName.isEmpty {
            let trimmedCategoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            newCategory = !trimmedCategoryName.isEmpty ? Category.findOrCreate(name: trimmedCategoryName, context: context) : nil
        }
        
        if let name = name {
            self.name = name
        }
        if let quantity = quantity {
            self.quantity = quantity
        }
        if let location = newLocation {
            let oldLocation = self.location
            self.location = location
            oldLocation?.checkAndCleanup(location: oldLocation!, context: context)
        }
        if let category = newCategory {
            let oldCategory = self.category
            self.category = category
            oldCategory?.checkAndCleanup(category: oldCategory!, context: context)
        }
        
        if let background = background {
            switch background {
            case let .symbol(symbol):
                self.symbol = symbol
                if let color = symbolColor {
                    self.symbolColor = color
                }
                self.imageData = nil
            case let .image(data):
                self.imageData = data
                self.symbol = nil
                self.symbolColor = .accentColor
            }
        } else if let color = symbolColor {
            // Allow updating symbolColor if passed without background
            self.symbolColor = color
        }
        
        self.modifiedDate = Date()
        
        try? context.save()
    }
    
    /// Deletes this Item, handles orphaned category/location, and cascades sortOrder.
    func deleteItem(
        context: ModelContext
    ) async {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let oldLocation = self.location
        let oldCategory = self.category
        let deletedOrder = self.sortOrder
        
        context.delete(self)
        
        // Clean up old location/category if they are empty
        oldLocation?.checkAndCleanup(location: oldLocation!, context: context)
        oldCategory?.checkAndCleanup(category: oldCategory!, context: context)
        
        // Cascade sortOrder
        let itemsToUpdate = items.filter { $0.sortOrder > deletedOrder }
        for otherItem in itemsToUpdate {
            otherItem.sortOrder -= 1
        }
        
        try? context.save()
    }
}

extension Location {
    /// Finds an existing location by name or creates a new one with the specified color and next available sort order.
    /// - If a location with the given name exists, it updates its color and returns it.
    /// - If no such location exists, it creates a new one with the next available sort order.
    /// - Parameters:
    /// - name: The name of the location to find or create.
    /// - color: The color to assign to the location.
    /// - locations: The list of existing locations to check against.
    /// - context: The ModelContext to insert new locations into.
    /// - Returns: The existing or newly created Location.
    /// This method is useful for ensuring that locations are unique by name while allowing color updates.
    static func findOrCreate(name: String, color: Color, context: ModelContext) -> Location {
        let locations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        
        if let existing = locations.first(where: { $0.name == name }) {
            existing.color = color
            return existing
        } else {
            let nextSortOrder = (locations.map { $0.sortOrder }.max() ?? 0) + 1
            let newLocation = Location(name: name, sortOrder: nextSortOrder, color: color)
            context.insert(newLocation)
            return newLocation
        }
    }
    
    func checkAndCleanup(location: Location, context: ModelContext) {
        // Save changes before cleanup
        try? context.save()
        
        if location.items?.isEmpty ?? true {
            context.delete(location)
        }
        
        try? context.save()
    }
}

extension Category {
    /// Finds an existing category by name or creates a new one with the next available sort order.
    /// - If a category with the given name exists, it returns that category.
    /// - If no such category exists, it creates a new one with the next available sort order.
    /// - Parameters:
    /// - name: The name of the category to find or create.
    /// - categories: The list of existing categories to check against.
    /// - Returns: The existing or newly created Category.
    /// This method is useful for ensuring that categories are unique by name.
    static func findOrCreate(name: String, context: ModelContext) -> Category {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        
        if let existing = categories.first(where: { $0.name == name }) {
            return existing
        } else {
            let nextSortOrder = (categories.map { $0.sortOrder }.max() ?? 0) + 1
            let newCategory = Category(name: name, sortOrder: nextSortOrder)
            context.insert(newCategory)
            return newCategory
        }
    }
    
    /// Checks if this category has no items and deletes it if empty.
    func checkAndCleanup(category: Category, context: ModelContext) {
        // Save changes before cleanup
        try? context.save()
        
        if category.items?.isEmpty ?? true {
            context.delete(category)
        }
        
        try? context.save()
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

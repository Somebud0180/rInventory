//
//  DataModelExtension.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/31/25.
//
//  Contains model functions/extensions for Item, Location, and Category.

import Foundation
import SwiftData
import SwiftUI

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
        
        // Trim and validate names
        let trimmedName = name.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find or create location and category
        let trimmedLocationName = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategoryName = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        let location = !trimmedLocationName.isEmpty ? Location.findOrCreate(name: trimmedLocationName, color: locationColor, context: context) : nil
        let category = !trimmedCategoryName.isEmpty ? Category.findOrCreate(name: trimmedCategoryName, context: context) : nil
        
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
            name: trimmedName,
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
        context: ModelContext,
        cloudKitSyncEngine: CloudKitSyncEngine? = nil
    ) async {
        // Trim and validate name
        let trimmedName = name?.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find or create Location
        var newLocation: Location?
        if let locationName = locationName, !locationName.isEmpty, let locationColor = locationColor {
            let trimmedLocationName = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
            newLocation = !trimmedLocationName.isEmpty ? Location.findOrCreate(name: trimmedLocationName, color: locationColor, context: context) : nil
        }
        
        // Find or create Category
        var newCategory: Category?
        if let categoryName = categoryName {
            let trimmedCategoryName = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
            newCategory = !trimmedCategoryName.isEmpty ? Category.findOrCreate(name: trimmedCategoryName, context: context) : Category(name: "nil")
        }
        
        if let name = trimmedName {
            self.name = name
        }
        if let quantity = quantity {
            self.quantity = quantity
        }
        if let location = newLocation {
            let oldLocation = self.location
            self.location = location
            await oldLocation?.checkAndCleanup(location: oldLocation!, context: context, cloudKitSyncEngine: cloudKitSyncEngine)
        }
        if let category = newCategory {
            let oldCategory = self.category
            if category.name == "nil" {
                self.category = nil
            } else {
                self.category = category
            }
            await oldCategory?.checkAndCleanup(category: oldCategory!, context: context, cloudKitSyncEngine: cloudKitSyncEngine)
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
        context: ModelContext,
        cloudKitSyncEngine: CloudKitSyncEngine? = nil
    ) async {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let oldLocation = self.location
        let oldCategory = self.category
        let deletedOrder = self.sortOrder
        
        // Add to tombstones in CloudKit if available
        if let syncEngine = cloudKitSyncEngine {
            await syncEngine.addTombstone(self.id.uuidString)
        }
        
        context.delete(self)
        
        // Clean up old location/category if they are empty
        await oldLocation?.checkAndCleanup(location: oldLocation!, context: context, cloudKitSyncEngine: cloudKitSyncEngine)
        await oldCategory?.checkAndCleanup(category: oldCategory!, context: context, cloudKitSyncEngine: cloudKitSyncEngine)
        
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
    
    @MainActor func checkAndCleanup(location: Location, context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) {
        // Save changes before cleanup
        try? context.save()
        
        if location.items?.isEmpty ?? true {
            if let syncEngine = cloudKitSyncEngine {
                syncEngine.addTombstone(self.id.uuidString)
            }
            
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
    @MainActor func checkAndCleanup(category: Category, context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) {
        // Save changes before cleanup
        try? context.save()
        
        if category.items?.isEmpty ?? true {
            if let syncEngine = cloudKitSyncEngine {
                syncEngine.addTombstone(self.id.uuidString)
            }
            
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

extension Sequence {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

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

enum ItemCardBackground {
    case symbol(String)
    case image(Data)
}

extension Item {
    /// Returns the background type for the item card, either symbol or image.
    func getBackgroundType() -> ItemCardBackground {
        if let imageData = self.imageData, !imageData.isEmpty {
            return .image(imageData)
        } else if let symbol = self.symbol {
            return .symbol(symbol)
        } else {
            return .symbol("questionmark")
        }
    }
    
#if !os(watchOS)
    @MainActor
    static func saveItem(name: String, quantity: Int, locationName: String, locationColor: Color,
                         categoryName: String, background: ItemCardBackground, symbolColor: Color, context: ModelContext) {
        let locationName = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryName = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
        let location = locationName.isEmpty ? nil : Location.findOrCreate(name: locationName, color: locationColor, context: context)
        let category = categoryName.isEmpty ? nil : Category.findOrCreate(name: categoryName, context: context)
        let order = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).map(\.sortOrder).max() ?? -1
        let item = Item(name: name.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines), quantity: max(quantity, 0),
                        location: location, category: category, sortOrder: order + 1)
        switch background {
        case .image(let data): item.imageData = data; item.symbol = nil; item.symbolColorData = nil
        case .symbol(let symbol): item.symbol = symbol; item.symbolColor = symbolColor
        }
        context.insert(item)
        SyncPersistence.saveReporting(context)
    }

    @MainActor
    func updateItem(name: String? = nil, quantity: Int? = nil, locationName: String? = nil,
                    locationColor: Color? = nil, categoryName: String? = nil, background: ItemCardBackground? = nil,
                    symbolColor: Color? = nil, context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) async {
        let oldLocation = self.location
        let oldCategory = self.category
        if let name { self.name = name.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let quantity { self.quantity = max(quantity, 0) }
        if let locationName {
            let trimmed = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
            self.location = trimmed.isEmpty ? nil : Location.findOrCreate(name: trimmed, color: locationColor ?? self.location?.color ?? .white, context: context)
        }
        if let categoryName {
            let trimmed = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
            self.category = trimmed.isEmpty ? nil : Category.findOrCreate(name: trimmed, context: context)
        }
        if let background {
            switch background {
            case .symbol(let symbol): self.symbol = symbol; self.imageData = nil; self.symbolColor = symbolColor ?? .accentColor
            case .image(let data): self.imageData = data; self.symbol = nil; self.symbolColorData = nil
            }
        } else if let symbolColor { self.symbolColor = symbolColor }
        if let oldLocation, oldLocation.id != self.location?.id { oldLocation.checkAndCleanup(location: oldLocation, context: context) }
        if let oldCategory, oldCategory.id != self.category?.id { oldCategory.checkAndCleanup(category: oldCategory, context: context) }
        SyncPersistence.saveReporting(context)
    }

    @MainActor
    func deleteItem(context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) async {
        let oldLocation = self.location
        let oldCategory = self.category
        let deletedOrder = self.sortOrder
        context.delete(self)
        if let oldLocation { oldLocation.checkAndCleanup(location: oldLocation, context: context) }
        if let oldCategory { oldCategory.checkAndCleanup(category: oldCategory, context: context) }
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] where item.id != self.id && item.sortOrder > deletedOrder {
            item.sortOrder -= 1
        }
        SyncPersistence.saveReporting(context)
    }
#endif
}

#if !os(watchOS)
extension Location {
    @MainActor
    static func findOrCreate(name: String, color: Color, context: ModelContext) -> Location {
        let locations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        if let existing = locations.first(where: { $0.name == name && !deletedIDs.contains($0.persistentModelID) }) {
            if existing.colorData != color.rgbaData { existing.color = color }
            return existing
        }
        let value = Location(name: name, sortOrder: (locations.map(\.sortOrder).max() ?? -1) + 1, color: color)
        context.insert(value)
        return value
    }
    @MainActor
    func checkAndCleanup(location: Location, context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) {
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        if !items.contains(where: { !deletedIDs.contains($0.persistentModelID) && $0.location?.id == location.id }) { context.delete(location) }
    }
}
extension Category {
    @MainActor
    static func findOrCreate(name: String, context: ModelContext) -> Category {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        if let existing = categories.first(where: { $0.name == name && !deletedIDs.contains($0.persistentModelID) }) { return existing }
        let value = Category(name: name, sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(value)
        return value
    }
    @MainActor
    func checkAndCleanup(category: Category, context: ModelContext, cloudKitSyncEngine: CloudKitSyncEngine? = nil) {
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        if !items.contains(where: { !deletedIDs.contains($0.persistentModelID) && $0.category?.id == category.id }) { context.delete(category) }
    }
}
#endif

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

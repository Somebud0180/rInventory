//
//  DataModel.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Contains the data model definitions for Item, Category, and Location.

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
    
    init(_ id: UUID = UUID(), name: String, quantity: Int, location: Location? = nil, category: Category? = nil, imageData: Data? = nil, symbol: String? = nil, symbolColor: Color? = .white, sortOrder: Int = 0, modifiedDate: Date = Date(), itemCreationDate: Date = Date()) {
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

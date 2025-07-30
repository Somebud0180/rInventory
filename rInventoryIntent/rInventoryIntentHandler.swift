//
//  rInventoryIntentHandler.swift
//  rInventoryIntent
//
//  Created by Ethan John Lagera on 7/29/25.
//
//  Handles the LocateItemIntent to find items in the inventory and return their locations.

import Foundation
import Intents
import SwiftData

class rInventoryIntentHandler: NSObject, LocateItemIntentHandling {
    let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    // MARK: - Intent Handling
    
    func handle(intent: LocateItemIntent, completion: @escaping (LocateItemIntentResponse) -> Void) {
        guard let itemName = intent.itemName else {
            let response = LocateItemIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // Attempt to find the item in the inventory
        if let location = findItemLocation(named: itemName) {
            let response = LocateItemIntentResponse.success(itemName: itemName, locationName: location)
            completion(response)
        } else {
            let response = LocateItemIntentResponse(code: .failure, userActivity: nil)
            completion(response)
        }
    }
    
    // MARK: - Resolution Methods
    
    func resolveItemName(for intent: LocateItemIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let itemName = intent.itemName, !itemName.isEmpty else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        
        // Check if the item exists in inventory
        let matchingItems = findMatchingItems(named: itemName)
        
        if matchingItems.isEmpty {
            // No matching items found
            completion(INStringResolutionResult.unsupported())
        } else if matchingItems.count == 1 {
            // Exactly one match found
            completion(INStringResolutionResult.success(with: matchingItems[0]))
        } else {
            // Multiple matches found, let Siri handle disambiguation
            completion(INStringResolutionResult.disambiguation(with: matchingItems))
        }
    }
    
    // MARK: - Helper Methods
    
    /// Find the location of an item with the given name
    /// - Parameter itemName: The name of the item to locate
    /// - Returns: The location name if found, nil otherwise
    private func findItemLocation(named itemName: String) -> String? {
        do {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate { item in item.name.localizedStandardContains(itemName)
            })
            
            let items = try context.fetch(descriptor)
            
            if let item = items.first, let location = item.location {
                return location.name
            }
            
            return nil
        } catch {
            print("Error finding item: \(error)")
            return nil
        }
    }
    
    /// Find items with names matching the given string
    /// - Parameter itemName: The name to search for
    /// - Returns: Array of matching item names
    private func findMatchingItems(named itemName: String) -> [String] {
        do {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate { item in
                item.name.localizedStandardContains(itemName)
            })
            
            let items = try context.fetch(descriptor)
            
            return items.map { $0.name }
        } catch {
            print("Error finding matching items: \(error)")
            return []
        }
    }
}

// MARK: - URL Extension

extension URL {
    static var applicationGroupContainerURL: URL {
        // Replace with your actual app group identifier
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.lagera.Inventory"
        ) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

// MARK: - Model Definitions

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
    
    init(id: UUID, name: String, quantity: Int, location: Location? = nil, category: Category? = nil, imageData: Data? = nil, symbol: String? = nil, symbolColorData: Data? = nil, sortOrder: Int, modifiedDate: Date, itemCreationDate: Date) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.location = location
        self.category = category
        self.imageData = imageData
        self.symbol = symbol
        self.symbolColorData = symbolColorData
        self.sortOrder = sortOrder
        self.modifiedDate = modifiedDate
        self.itemCreationDate = itemCreationDate
    }
}

@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var items: [Item]?
    
    init(id: UUID = UUID(), name: String = "", items: [Item]? = nil) {
        self.id = id
        self.name = name
        self.items = items
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var items: [Item]?
    
    init(id: UUID = UUID(), name: String = "", items: [Item]? = nil) {
        self.id = id
        self.name = name
        self.items = items
    }
}

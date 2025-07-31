//
//  LocateItem.swift
//  rInventoryIntent
//
//  Created by Ethan John Lagera on 7/30/25.
//
//  This file contains the LocateItem intent for finding items.

import Foundation
import AppIntents
import SwiftData
import SwiftUI
import os

// Logger for debugging
private let logger = Logger(subsystem: "com.lagera.Inventory", category: "LocateItemIntent")

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct LocateItem: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Location.self
        ])
        let containerURL = URL.applicationGroupContainerURL
        
        // Improved logging for debugging
        logger.debug("Using app group container at: \(containerURL.path)")
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: containerURL.appendingPathComponent("rInventory.store"),
            cloudKitDatabase: .private("iCloud.com.lagera.Inventory")
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.debug("Successfully created model container")
            return container
        } catch {
            logger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    static let intentClassName = "LocateItemIntent"
    
    static var title: LocalizedStringResource = "Find Item"
    static var description = IntentDescription("Find where an item is located via its name")
    
    @Parameter(title: "Item")
    var itemName: String?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Where is \(\.$itemName) in my inventory")
    }
    
    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$itemName)) { itemName in
            DisplayRepresentation(
                title: "Where is \(itemName ?? "this item") in my inventory",
                subtitle: ""
            )
        }
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let itemName = itemName, !itemName.isEmpty else {
            logger.error("No item name provided")
            return .result(value: "Please provide an item name to search for.")
        }
        
        logger.debug("Searching for item: \(itemName)")
        
        do {
            let context = ModelContext(LocateItem.sharedModelContainer)
            let fetchDescriptor = FetchDescriptor<Item>(predicate: #Predicate { item in
                item.name.localizedStandardContains(itemName)
            })
            
            let foundItems = try context.fetch(fetchDescriptor)
            logger.debug("Found \(foundItems.count) items matching '\(itemName)'")
            
            if foundItems.isEmpty {
                return .result(value: "I couldn't find '\(itemName)' in your inventory.")
            } else if foundItems.count > 1 {
                let itemNames = foundItems.map({ $0.name }).joined(separator: ", ")
                return .result(value: "\(itemNames) are in your inventory. Please specify which one you want.")
                
            } else if let modelItemName = foundItems.first?.name, let location = foundItems.first?.location {
                return .result(value: "\(modelItemName) is at the \(location.name).")
            } else if let modelItemName = foundItems.first?.name {
                return .result(value: "\(modelItemName) is in your inventory but has no specified location.")
            } else {
                return .result(value: "There was an issue finding that item.")
            }
        } catch {
            logger.error("Error fetching items: \(error.localizedDescription)")
            return .result(value: "Sorry, I encountered an error while searching for that item.")
        }
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
fileprivate extension IntentDialog {
    static func itemNameParameterPrompt(itemName: String) -> Self {
        "Where is \(itemName) in my inventory"
    }
    static func itemNameParameterDisambiguationIntro(itemNames: String) -> Self {
        "\(itemNames) are in your inventory. Please specify which one do you want."
    }
    static func responseSuccess(itemName: String, locationName: String) -> Self {
        "\(itemName) is at the \(locationName)."
    }
    static var responseFailure: Self {
        "There was an issue finding that item."
    }
}

extension URL {
    static var applicationGroupContainerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.lagera.Inventory"
        ) else {
            logger.error("Failed to get app group container URL, falling back to temporary directory")
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return url
    }
}

// MARK: - Model Definitions

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Int = 0
    var location: Location?
    var sortOrder: Int = 0
    var modifiedDate: Date = Date()
    var itemCreationDate: Date = Date()
    
    init(_ id: UUID = UUID(), name: String, quantity: Int, location: Location? = nil, sortOrder: Int = 0, modifiedDate: Date = Date(), itemCreationDate: Date = Date()) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.location = location
        self.sortOrder = sortOrder
        self.modifiedDate = modifiedDate
        self.itemCreationDate = itemCreationDate
    }
}

@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var displayInRow: Bool = true
    
    init(_ id: UUID = UUID(), name: String, sortOrder: Int = 0, displayInRow: Bool = true) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.displayInRow = displayInRow
    }
}

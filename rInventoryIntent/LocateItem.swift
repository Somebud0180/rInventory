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

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct LocateItem: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let containerURL = URL.applicationGroupContainerURL
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: containerURL.appendingPathComponent("rInventory.store"),
            cloudKitDatabase: .private("iCloud.com.lagera.Inventory")
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
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
                title: "Where is \(itemName!) in my inventory",
                subtitle: ""
            )
        }
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let itemName else {
            return .result(value: "There was an issue finding that item.")
        }
        
        let context = ModelContext(LocateItem.sharedModelContainer)
        let fetchDescriptor = FetchDescriptor<Item>(predicate: #Predicate { item in
            item.name.localizedStandardContains(itemName)
        })
        
        let foundModelItems = try? context.fetch(fetchDescriptor)
        // Turn foundModelItems into non-optional
        let foundItems = foundModelItems ?? []
        
        if foundItems.isEmpty {
            return .result(value: "There was an issue finding that item.")
        } else if foundItems.count > 1 {
            let itemNames = foundItems.map({ $0.name }).joined(separator: ", ")
            return .result(value: "\(itemNames) are in your inventory. Please specify which one do you want.")
                
        } else if let modelItemName = foundItems.first?.name, let locationName = foundItems.first?.location?.name {
            return .result(value: "\(modelItemName) is at the \(locationName).")
        } else {
            return .result(value: "There was an issue finding that item.")
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

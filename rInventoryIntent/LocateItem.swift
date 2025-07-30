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
            return .result(value: "That item could not be found.")
        } else if foundItems.count > 1 {
            let itemNames = foundItems.map({ $0.name })
            return .result(value: "There are \(foundItems.count) items named ‘\(itemName)’ in your inventory. Please specify which one.")
        } else if let itemName = foundItems.first?.name, let locationName = foundItems.first?.location?.name {
            return .result(value: "\(itemName) is at the \(locationName).")
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
    static func itemNameParameterDisambiguationIntro(count: Int, itemName: String) -> Self {
        "There are \(count) items named ‘\(itemName)’ in your inventory."
    }
    static func itemNameParameterConfirmation(itemName: String) -> Self {
        "Just to confirm, you wanted ‘\(itemName)’?"
    }
    static func responseSuccess(itemName: String, locationName: String) -> Self {
        "\(itemName) is at the \(locationName)."
    }
    static var responseFailure: Self {
        "There was an issue finding that item."
    }
}

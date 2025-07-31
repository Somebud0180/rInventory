//
//  LocateItem.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/31/25.
//

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
        guard let itemName = itemName, !itemName.isEmpty else {
            return .result(value: "Please provide an item name to search for.")
        }
        
        let modelContext = ModelContext(LocateItem.sharedModelContainer)
        let fetchDescriptor = FetchDescriptor<Item>(predicate: #Predicate { item in
            item.name.localizedStandardContains(itemName)
        })
        
        let foundItems = try modelContext.fetch(fetchDescriptor)
        
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
    static func responseFailure(itemName: String) -> Self {
        "There was an issue."
    }
    static var responseUnsupported: Self {
        "There was a problem finding that item."
    }
}


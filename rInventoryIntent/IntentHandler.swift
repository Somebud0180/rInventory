//
//  IntentHandler.swift
//  rInventoryIntent
//
//  Created by Ethan John Lagera on 7/29/25.
//
//  This file handles the intents for the app, primarily used for Siri integration.

import SwiftData
import Intents

class IntentHandler: INExtension {
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
    
    override func handler(for intent: INIntent) -> Any {
        if intent is LocateItemIntent {
            return rInventoryIntentHandler(modelContainer: IntentHandler.sharedModelContainer)
        }
        
        fatalError("Unhandled intent type: \(intent)")
    }
}

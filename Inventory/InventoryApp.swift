//
//  InventoryApp.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData
import CloudKit

@main
struct InventoryApp: App {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var syncEngine: CloudKitSyncEngine
    
    init() {
        self._syncEngine = StateObject(wrappedValue: CloudKitSyncEngine(modelContext: InventoryApp.sharedModelContainer.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(syncEngine: syncEngine)
        }
        .modelContainer(InventoryApp.sharedModelContainer)
    }
}

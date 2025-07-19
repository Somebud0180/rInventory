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
    
    init() {
        self._syncEngine = StateObject(wrappedValue: CloudKitSyncEngine(modelContext: InventoryApp.sharedModelContainer.mainContext))
    }
    
    @StateObject private var syncEngine: CloudKitSyncEngine
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    var body: some Scene {
        let context = InventoryApp.sharedModelContainer.mainContext
        let configFetch = FetchDescriptor<Config>()
        let config = try? context.fetch(configFetch)
        
        WindowGroup {
            ContentView(syncEngine: syncEngine)
                .preferredColorScheme(config?.first?.resolvedColorScheme(systemColorScheme: colorScheme))
        }
        .modelContainer(InventoryApp.sharedModelContainer)
    }
}

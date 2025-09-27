//
//  InventoryApp.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 8/11/25.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - AppDefaults for App Configuration
class AppDefaults: ObservableObject {
    static let shared = AppDefaults()
    private let defaults = UserDefaults.standard
    
    @Published var showCounterForSingleItems: Bool
    @Published var defaultInventorySort: Int
    
    private enum Keys {
        static let showCounterForSingleItems = "showCounterForSingleItems"
        static let defaultInventorySort = "defaultInventorySort"
    }
    
    private init() {
        showCounterForSingleItems = defaults.object(forKey: Keys.showCounterForSingleItems) as? Bool ?? true
        defaultInventorySort = defaults.integer(forKey: Keys.defaultInventorySort)
        
        // Add observers to save on change
        $showCounterForSingleItems.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showCounterForSingleItems) }.store(in: &cancellables)
        $defaultInventorySort.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.defaultInventorySort) }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

@main
struct Inventory_WatchApp: App {
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
    
    init() {
        self._syncEngine = StateObject(wrappedValue: CloudKitSyncEngine(modelContext: Inventory_WatchApp.sharedModelContainer.mainContext))
    }
    
    @StateObject private var syncEngine: CloudKitSyncEngine
    @StateObject private var appDefaults = AppDefaults.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    var body: some Scene {
        WindowGroup {
            ContentView(syncEngine: syncEngine)
                .environmentObject(appDefaults)
        }
        .modelContainer(Inventory_WatchApp.sharedModelContainer)
    }
}

extension URL {
    static var applicationGroupContainerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.lagera.Inventory"
        ) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}


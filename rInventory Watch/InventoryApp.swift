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
    @Published var showHiddenCategories: Bool = true
    @Published var showHiddenLocations: Bool = true
    
    private enum Keys {
        static let showCounterForSingleItems = "showCounterForSingleItems"
        static let defaultInventorySort = "defaultInventorySort"
        static let showHiddenCategories = "showHiddenCategories"
        static let showHiddenLocations = "showHiddenLocations"
    }
    
    private init() {
        showCounterForSingleItems = defaults.object(forKey: Keys.showCounterForSingleItems) as? Bool ?? true
        defaultInventorySort = defaults.integer(forKey: Keys.defaultInventorySort)
        showHiddenCategories = defaults.object(forKey: Keys.showHiddenCategories) as? Bool ?? false
        showHiddenLocations = defaults.object(forKey: Keys.showHiddenLocations) as? Bool ?? false
        
        // Add observers to save on change
        $showCounterForSingleItems.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showCounterForSingleItems) }.store(in: &cancellables)
        $defaultInventorySort.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.defaultInventorySort) }.store(in: &cancellables)
        $showHiddenCategories.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showHiddenCategories) }.store(in: &cancellables)
        $showHiddenLocations.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showHiddenLocations) }.store(in: &cancellables)
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
    
    @StateObject private var appDefaults = AppDefaults.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDefaults)
        }
        .modelContainer(Inventory_WatchApp.sharedModelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                // Clear memory caches when app is backgrounded
                ImageCaches.purgeMemoryCaches()
            }
        }
    }
}

extension URL {
    static var applicationGroupContainerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.lagera.Inventory"
        ) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

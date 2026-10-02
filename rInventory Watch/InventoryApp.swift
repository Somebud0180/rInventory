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
    static var sharedModelContainer: ModelContainer { InventoryStoreCoordinator.shared.container }
    @StateObject private var coordinator = InventoryStoreCoordinator.shared
    @StateObject private var appDefaults = AppDefaults.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var visibility = WatchVisibilityPreferences.shared

    var body: some Scene {
        WindowGroup {
            ContentView(syncEngine: coordinator.engine)
                .environmentObject(appDefaults)
                .environmentObject(visibility)
                .id(coordinator.storeKey)
                .environmentObject(coordinator)
                .modelContainer(coordinator.container)
                .task { await coordinator.refreshAccount() }
        }

        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await coordinator.refreshAccount() }
            } else if scenePhase == .background {
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

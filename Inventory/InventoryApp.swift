//
//  InventoryApp.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData
import CloudKit

// MARK: - AppDefaults for App Configuration
class AppDefaults {
    static let shared = AppDefaults()
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let themeMode = "themeMode"
        static let showCounterForSingleItems = "showCounterForSingleItems"
        static let defaultInventorySort = "defaultInventorySort"
    }
    
    var themeMode: Int {
        get { defaults.integer(forKey: Keys.themeMode) }
        set { defaults.set(newValue, forKey: Keys.themeMode) }
    }
    
    var showCounterForSingleItems: Bool {
        get { defaults.object(forKey: Keys.showCounterForSingleItems) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.showCounterForSingleItems) }
    }
    
    var defaultInventorySort: Int {
        get { defaults.integer(forKey: Keys.defaultInventorySort) }
        set { defaults.set(newValue, forKey: Keys.defaultInventorySort) }
    }
    
    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default: return systemColorScheme
        }
    }
}

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
        WindowGroup {
            ContentView(syncEngine: syncEngine)
                .preferredColorScheme(AppDefaults.shared.resolvedColorScheme(systemColorScheme: colorScheme))
        }
        .modelContainer(InventoryApp.sharedModelContainer)
    }
}

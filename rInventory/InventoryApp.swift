//
//  InventoryApp.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData
import CloudKit
import SwiftyCrop
import Combine

// MARK: - AppDefaults for App Configuration
class AppDefaults: ObservableObject {
    static let shared = AppDefaults()
    private let defaults = UserDefaults.standard
    
    @Published var themeMode: Int
    @Published var showCounterForSingleItems: Bool
    @Published var defaultInventorySort: Int
    @Published var showInventoryAsRows: Bool
    @Published var showHiddenCategoriesInGrid: Bool
    @Published var showHiddenLocationsInGrid: Bool
    @Published var showRecentlyAdded: Bool
    @Published var showCategories: Bool
    @Published var showLocations: Bool
    
    private enum Keys {
        static let themeMode = "themeMode"
        static let showCounterForSingleItems = "showCounterForSingleItems"
        static let defaultInventorySort = "defaultInventorySort"
        static let showInventoryAsRows = "showInventoryAsRows"
        static let showHiddenCategoriesInGrid = "showHiddenCategoriesInGrid"
        static let showHiddenLocationsInGrid = "showHiddenLocationsInGrid"
        static let showRecentlyAdded = "showRecentlyAdded"
        static let showCategories = "showCategories"
        static let showLocations = "showLocations"
    }
    
    private init() {
        themeMode = defaults.integer(forKey: Keys.themeMode) 
        showCounterForSingleItems = defaults.object(forKey: Keys.showCounterForSingleItems) as? Bool ?? true
        defaultInventorySort = defaults.integer(forKey: Keys.defaultInventorySort)
        showInventoryAsRows = defaults.object(forKey: Keys.showInventoryAsRows) as? Bool ?? true
        showHiddenCategoriesInGrid = defaults.object(forKey: Keys.showHiddenCategoriesInGrid) as? Bool ?? true
        showHiddenLocationsInGrid = defaults.object(forKey: Keys.showHiddenLocationsInGrid) as? Bool ?? true
        showRecentlyAdded = defaults.object(forKey: Keys.showRecentlyAdded) as? Bool ?? true
        showCategories = defaults.object(forKey: Keys.showCategories) as? Bool ?? true
        showLocations = defaults.object(forKey: Keys.showLocations) as? Bool ?? true
        
        // Add observers to save on change
        $themeMode.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.themeMode) }.store(in: &cancellables)
        $showCounterForSingleItems.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showCounterForSingleItems) }.store(in: &cancellables)
        $defaultInventorySort.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.defaultInventorySort) }.store(in: &cancellables)
        $showInventoryAsRows.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showInventoryAsRows) }.store(in: &cancellables)
        $showHiddenCategoriesInGrid.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showHiddenCategoriesInGrid) }.store(in: &cancellables)
        $showHiddenLocationsInGrid.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showHiddenLocationsInGrid) }.store(in: &cancellables)
        $showRecentlyAdded.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showRecentlyAdded) }.store(in: &cancellables)
        $showCategories.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showCategories) }.store(in: &cancellables)
        $showLocations.sink { [weak self] value in self?.defaults.set(value, forKey: Keys.showLocations) }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func resolvedColorScheme() -> ColorScheme? {
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

var swiftyCropConfiguration: SwiftyCropConfiguration {
    SwiftyCropConfiguration(
        maxMagnificationScale: 4.0,
        maskRadius: 130,
        cropImageCircular: false,
        rotateImage: false,
        rotateImageWithButtons: true,
        usesLiquidGlassDesign: usesLiquidGlass,
        zoomSensitivity: 4.0,
        rectAspectRatio: 4/3,
        texts: SwiftyCropConfiguration.Texts(
            cancelButton: "Cancel",
            interactionInstructions: "",
            saveButton: "Save"
        ),
        fonts: SwiftyCropConfiguration.Fonts(
            cancelButton: Font.system(size: 12),
            interactionInstructions: Font.system(size: 14),
            saveButton: Font.system(size: 12)
        ),
        colors: SwiftyCropConfiguration.Colors(
            cancelButton: Color.red,
            interactionInstructions: Color.white,
            saveButton: Color.blue,
            background: Color.gray
        )
    )
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
    @StateObject private var appDefaults = AppDefaults.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    var body: some Scene {
        WindowGroup {
            ContentView(syncEngine: syncEngine)
                .id(appDefaults.themeMode)
                .environmentObject(appDefaults)
                .preferredColorScheme(appDefaults.resolvedColorScheme())
        }
        .modelContainer(InventoryApp.sharedModelContainer)
    }
}

//
//  InventoryApp.swift
//  Inventory
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
        get { defaults.object(forKey: Keys.showCounterForSingleItems) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showCounterForSingleItems) }
    }
    
    var defaultInventorySort: Int {
        get { defaults.integer(forKey: Keys.defaultInventorySort) }
        set { defaults.set(newValue, forKey: Keys.defaultInventorySort) }
    }
    
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

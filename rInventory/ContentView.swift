//  ContentView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view of the Inventory app, containing tabs for Home, Settings, and Search.

import SwiftUI
import SwiftData
import Foundation
import CloudKit

// Helper to determine if Liquid Glass design is available
let usesLiquidGlass: Bool = {
    if #available(iOS 26.0, *) {
        return true
    } else {
        return false
    }
}()

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var syncEngine: CloudKitSyncEngine
    @Query private var items: [Item]
    
    @SceneStorage("ContentView.tabSelection") var tabSelection: Int = TabSelection.home.rawValue
    
    // User Activity & State Restoration support
    private enum TabSelection: Int {
        case home = 0, settings = 1, search = 2
    }
    
    private var currentTab: TabSelection {
        get { TabSelection(rawValue: tabSelection) ?? .home }
        set { tabSelection = newValue.rawValue }
    }
    
    @State private var continuedActivity: NSUserActivity? = nil
    @State private var showInventoryGridView: Bool = false
    @State private var showItemCreationView: Bool = false
    @State private var showInteractiveCreationView: Bool = false
    @State private var showItemView: Bool = false
    @State private var selectedItem: Item? = nil
    
    var body: some View {
        return tabView()
            .onChange(of: selectedItem) {
                if selectedItem != nil {
                    showItemView = true
                }
            }
            .sheet(isPresented: $showItemView) {
                ItemView(syncEngine: syncEngine, item: $selectedItem)
            }
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .animatedFullscreenCover(isPresented: $showInteractiveCreationView) {
                InteractiveCreationView(isPresented: $showInteractiveCreationView)
            }
            .fullScreenCover(isPresented: $showInventoryGridView, onDismiss: { continuedActivity = nil }) {
                if let activity = continuedActivity {
                    InventoryGridView(
                        syncEngine: syncEngine,
                        title: activity.userInfo?[inventoryGridTitleKey] as? String ?? "Inventory",
                        predicate: activity.userInfo?[inventoryGridPredicateKey] as? String,
                        showCategoryPicker: activity.userInfo?[inventoryGridCategoryKey] as? Bool ?? false,
                        showSortPicker: activity.userInfo?[inventoryGridSortKey] as? Bool ?? false,
                        isInventoryActive: .constant(false),
                        isInventoryGridActive: .constant(false)
                    )
                }
            }
            .onContinueUserActivity(inventoryActivityType) { _ in
                tabSelection = TabSelection.home.rawValue
            }
            .onContinueUserActivity(inventoryGridActivityType) { activity in
                continuedActivity = activity
                tabSelection = TabSelection.home.rawValue
            }
            .onContinueUserActivity(settingsActivityType) { _ in
                tabSelection = TabSelection.settings.rawValue
            }
            .onContinueUserActivity(searchActivityType) { _ in
                tabSelection = TabSelection.search.rawValue
            }
            .onChange(of: continuedActivity) {
                if continuedActivity != nil {
                    showInventoryGridView = true
                }
            }
    }
    
    
    private func tabView() -> some View {
        if #available(iOS 18.0, *) {
            return TabView(selection: $tabSelection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(syncEngine: syncEngine,
                                  showItemCreationView: $showItemCreationView,
                                  showInteractiveCreationView: $showInteractiveCreationView,
                                  isActive: currentTab == .home)
                }
                
                // Settings Tab
                Tab("Settings", systemImage: "gearshape", value: 1) {
                    SettingsView(syncEngine: syncEngine, isActive: currentTab == .settings)
                }
                
                // Search Action
                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView(syncEngine: syncEngine, isActive: currentTab == .search)
                }
            }
        } else {
            return TabView(selection: $tabSelection) {
                // Home Tab
                InventoryView(syncEngine: syncEngine,
                              showItemCreationView: $showItemCreationView,
                              showInteractiveCreationView: $showInteractiveCreationView,
                              isActive: currentTab == .home)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0) // Tag for Home Tab
                
                // Settings Tab
                SettingsView(syncEngine: syncEngine, isActive: currentTab == .settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(1) // Tag for Settings Tab
                
                // Search Tab
                SearchView(syncEngine: syncEngine, isActive: currentTab == .search)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2) // Tag for Search Tab
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    ContentView(syncEngine: syncEngine)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

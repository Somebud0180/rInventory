//  ContentView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view of the Inventory app, containing tabs for Home, Settings, and Search.

import SwiftUI
import SwiftData
import Foundation
import CloudKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @ObservedObject var syncEngine: CloudKitSyncEngine
    
    // User Activity & State Restoration support
    private enum TabSelection: Int {
        case home = 0, settings = 1, search = 2
    }
    
    @SceneStorage("ContentView.tabSelection") var tabSelection: Int = TabSelection.home.rawValue
    
    private var currentTab: TabSelection {
        get { TabSelection(rawValue: tabSelection) ?? .home }
        set { tabSelection = newValue.rawValue }
    }
    
    
    @State private var selectedItem: Item? = nil
    @State private var showItemCreationView: Bool = false
    @State private var showItemView: Bool = false
    
    init(syncEngine: CloudKitSyncEngine) {
        self.syncEngine = syncEngine
    }
    
    var body: some View {
        let activityType: String?
        let isActive: Bool
        
        switch currentTab {
        case .home:
            activityType = inventoryActivityType
            isActive = true
        case .settings:
            activityType = settingsActivityType
            isActive = true
        case .search:
            activityType = searchActivityType
            isActive = true
        }
        
        return tabView()
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .onChange(of: selectedItem) {
                if selectedItem != nil {
                    showItemView = true
                }
            }
            .sheet(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                if !(selectedItem == nil), let selectedItem = selectedItem {
                    ItemView(item: bindingForItem(selectedItem))
                        .transition(.blurReplace)
                } else {
                    ProgressView("Loading item...")
                }
            }
            .userActivity(activityType ?? "", isActive: isActive) { activity in
                switch currentTab {
                case .home:
                    activity.title = "Viewing Inventory"
                case .settings:
                    activity.title = "Managing Settings"
                case .search:
                    activity.title = "Searching Inventory"
                }
                activity.userInfo = ["tabSelection": currentTab.rawValue]
            }
            .onContinueUserActivity(inventoryActivityType) { _ in
                tabSelection = TabSelection.home.rawValue
            }
            .onContinueUserActivity(settingsActivityType) { _ in
                tabSelection = TabSelection.settings.rawValue
            }
            .onContinueUserActivity(searchActivityType) { _ in
                tabSelection = TabSelection.search.rawValue
            }
    }
    
    
    private func tabView() -> some View {
        if #available(iOS 18.0, *) {
            return TabView(selection: $tabSelection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(syncEngine: syncEngine, showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem, isActive: currentTab == .home)
                }
                
                // Settings Tab
                Tab("Settings", systemImage: "gearshape", value: 1) {
                    SettingsView(isActive: currentTab == .settings)
                }
                
                // Search Action
                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView(showItemView: $showItemView, selectedItem: $selectedItem, isActive: currentTab == .search)
                }
            }
        } else {
            return TabView(selection: $tabSelection) {
                // Home Tab
                InventoryView(syncEngine: syncEngine, showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem, isActive: currentTab == .home)
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0) // Tag for Home Tab
                
                // Settings Tab
                SettingsView(isActive: currentTab == .settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(1) // Tag for Settings Tab
                
                // Search Tab
                SearchView(showItemView: $showItemView, selectedItem: $selectedItem, isActive: currentTab == .search)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2) // Tag for Search Tab
            }
        }
    }
    
    private func bindingForItem(_ item: Item) -> Binding<Item> {
        return Binding(
            get: {
                // Fetch the item from the model context
                if let fetchedItem = items.first(where: { $0.id == item.id }) {
                    return fetchedItem
                }
                return item
            },
            set: { newValue in
                // Changes are automatically persisted through SwiftData's model context
                // No explicit save needed as SwiftData handles this automatically
            }
        )
    }
    
    private func addItem() {
        showItemCreationView = true
    }
}

#Preview {
    let tempContainer = try! ModelContainer(for: Item.self, Location.self, Category.self)
    let engine = CloudKitSyncEngine(modelContext: tempContainer.mainContext)
    ContentView(syncEngine: engine)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

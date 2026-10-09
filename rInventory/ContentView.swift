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
    @ObservedObject private var actionRouter = InventoryActionRouter.shared
    @EnvironmentObject private var appDefaults: AppDefaults
    @Environment(\.scenePhase) private var scenePhase
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
    
    @State private var routingReady = false
    @State private var continuedActivity: NSUserActivity? = nil
    @State private var showInventoryGridView: Bool = false
    @State private var showItemCreationView: Bool = false
    @State private var showInteractiveCreationView: Bool = false
    @State private var showItemView: Bool = false
    @State private var selectedItem: Item? = nil
    
    var body: some View {
        return tabView()
            .task {
                // Account refresh can replace this root view; keep the action pending until it settles.
                await InventoryStoreCoordinator.shared.refreshAccount()
                guard !Task.isCancelled else { return }
                routingReady = true
                handleNewItemRequest()
            }
            .onChange(of: actionRouter.newItemRequested) { handleNewItemRequest() }
            .onChange(of: scenePhase) { handleNewItemRequest() }
            .onChange(of: selectedItem) {
                if selectedItem != nil {
                    showItemView = true
                }
            }
            .sheet(isPresented: $showItemView, onDismiss: handleNewItemRequest) {
                ItemView(syncEngine: syncEngine, item: $selectedItem)
            }
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .animatedFullscreenCover(isPresented: $showInteractiveCreationView) {
                InteractiveCreationView(isPresented: $showInteractiveCreationView)
            }
            .fullScreenCover(isPresented: $showInventoryGridView, onDismiss: { continuedActivity = nil; handleNewItemRequest() }) {
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
    
    
    private func handleNewItemRequest() {
        guard routingReady, actionRouter.newItemRequested, scenePhase == .active else { return }
        tabSelection = TabSelection.home.rawValue
        if showItemView || showInventoryGridView {
            showItemView = false
            showInventoryGridView = false
            return // Finish dismissing before presenting the creation flow.
        }
        actionRouter.newItemRequested = false
        guard !showItemCreationView, !showInteractiveCreationView else { return }
        if appDefaults.useInteractiveCreation {
            showInteractiveCreationView = true
        } else {
            showItemCreationView = true
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
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: SyncPersistence.schema, configurations: [ModelConfiguration(schema: SyncPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])))
    
    ContentView(syncEngine: syncEngine)
        .environmentObject(AppDefaults.shared)
        .environmentObject(InventoryStoreCoordinator.shared)
        .modelContainer(for: [Item.self, Location.self, Category.self, SyncRecordState.self, SyncCheckpoint.self], inMemory: true)
}

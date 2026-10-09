//
//  SettingsView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/27/25.
//

import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @EnvironmentObject private var syncEngine: CloudKitSyncEngine
    @EnvironmentObject private var coordinator: InventoryStoreCoordinator
    @EnvironmentObject private var visibility: WatchVisibilityPreferences
    @EnvironmentObject var appDefaults: AppDefaults
    
    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud Sync") {
                    if let message = coordinator.errorMessage { Text(message).foregroundStyle(.secondary) }
                    switch syncEngine.syncState {
                    case .syncing: ProgressView("Syncing inventory")
                    case .error(let message): Text(message).foregroundStyle(.secondary)
                    default: Text(syncEngine.isAccountAvailable ? "iCloud connected" : "iCloud unavailable")
                    }
                    Button("Sync Now") { Task { await coordinator.refreshAccount(force: true) } }
                        .disabled(syncEngine.syncState == .syncing)
#if DEBUG
                    Button("Repair & Re-sync") { Task { await syncEngine.forceFullResync() } }
                        .disabled(!syncEngine.isAccountAvailable || syncEngine.syncState == .syncing)
#endif // Debug
                }

                Group {
                    Section(header: Text("Visuals")) {
                        Toggle("Show Counter for Single Items", isOn: $appDefaults.showCounterForSingleItems)
                    }
                }
                
                Group {
                    Section(header: Text("Locations & Categories")) {
                        Toggle("Show Hidden Categories", isOn: $appDefaults.showHiddenCategories)
                        Toggle("Show Hidden Locations", isOn: $appDefaults.showHiddenLocations)
                    }
                    
                    Section {
                        NavigationLink(destination: CategoriesSettingsView()) {
                            HStack {
                                Text("Categories")
                                Spacer()
                            }
                        }
                        
                        NavigationLink(destination: LocationsSettingsView()) {
                            HStack {
                                Text("Locations")
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CategoriesSettingsView: View {
    @EnvironmentObject private var visibility: WatchVisibilityPreferences
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    
    var body: some View {
        List {
            ForEach(categories, id: \.id) { category in
                Button(action: {
                    // Toggle visibility for just this category
                    visibility.toggle(zone: SyncPersistence.categoriesZone, id: category.id, fallback: category.displayInRow)
                }) {
                    HStack {
                        Text(category.name)
                        Spacer()
                        Image(systemName: visibility.visible(zone: SyncPersistence.categoriesZone, id: category.id, fallback: category.displayInRow) ? "checkmark.circle.fill" : "circle")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .navigationTitle("Categories")
    }
}

struct LocationsSettingsView: View {
    @EnvironmentObject private var visibility: WatchVisibilityPreferences
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Location.sortOrder, order: .forward) private var locations: [Location]
    
    var body: some View {
        List {
            ForEach(locations, id: \.id) { location in
                Button(action: {
                    // Toggle visibility for just this location
                    visibility.toggle(zone: SyncPersistence.locationsZone, id: location.id, fallback: location.displayInRow)
                }) {
                    HStack {
                        Text(location.name)
                        Spacer()
                        Image(systemName: visibility.visible(zone: SyncPersistence.locationsZone, id: location.id, fallback: location.displayInRow) ? "checkmark.circle.fill" : "circle")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .navigationTitle("Locations")
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Item.self, Location.self, Category.self, SyncRecordState.self, SyncCheckpoint.self], inMemory: true)
        .environmentObject(AppDefaults.shared)
        .environmentObject(InventoryStoreCoordinator.shared)
        .environmentObject(WatchVisibilityPreferences.shared)
        .environmentObject(InventoryStoreCoordinator.shared.engine)
}

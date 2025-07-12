//  ContentView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view of the Inventory app, containing tabs for Home, Settings, and Search.

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State var tabSelection: Int = 0
    @State private var selectedItem: Item? = nil
    @State private var showItemCreationView: Bool = false
    @State private var showItemView: Bool = false
    
    var body: some View {
        tabView()
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .sheet(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                if !(selectedItem == nil), let selectedItem = selectedItem {
                    ItemView(item: bindingForItem(selectedItem))
                } else {
                    ProgressView("Loading item...")
                }
            }
    }
    
    
    private func tabView() -> some View {
        if #available(iOS 18.0, *) {
            return TabView(selection: $tabSelection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem)
                }
                
                // Settings Tab
                Tab("Settings", systemImage: "gearshape", value: 1) {
                    SettingsView()
                }
                
                // Search Action
                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView(showItemView: $showItemView, selectedItem: $selectedItem)
                }
            }
        } else {
            return TabView(selection: $tabSelection) {
                // Home Tab
                InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem)
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0) // Tag for Home Tab
                
                // Settings Tab
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(1) // Tag for Settings Tab
                
                // Search Tab
                SearchView(showItemView: $showItemView, selectedItem: $selectedItem)
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
    ContentView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Location.self)
        .modelContainer(for: Category.self)
}

//  ContentView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State var selection: Int = 0
    @State var selectedItem: Item? = nil
    @State var showItemCreationView: Bool = false
    @State var showItemView: Bool = false
    
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem)
                }
                
                // Settings Tab
                Tab("Settings", systemImage: "gearshape", value: 1) {
                    NavigationView {
                        Text("Settings")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .navigationViewStyle(.stack)
                }
                
                // Search Action
                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView(showItemView: $showItemView, selectedItem: $selectedItem)
                }
            }
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .sheet(isPresented: $showItemView) {
                if let selectedItem = selectedItem {
                    ItemView(item: bindingForItem(selectedItem))
                }
            }
        } else {
            TabView(selection: $selection) {
                // Home Tab
                InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem)
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0) // Tag for Home Tab
                
                // Settings Tab
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(1) // Tag for Settings Tab
            }
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            .sheet(isPresented: $showItemView) {
                if let selectedItem = selectedItem {
                    ItemView(item: bindingForItem(selectedItem))
                }
            }
        }
    }
    
    private func bindingForItem(_ item: Item) -> Binding<Item> {
        return Binding(
            get: {
                // Return the current item from the model context to ensure we have the latest data
                if let currentItem = items.first(where: { $0.id == item.id }) {
                    return currentItem
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
}

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
    @State private var showItemCreationView: Bool = false
    
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(showItemCreationView: $showItemCreationView)
                }
                
                // Settings Tab
                Tab("Settings", systemImage: "gearshape", value: 1) {
                    NavigationView {
                        Text("Settings")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                }
                
                // Search Action
                Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                    SearchView()
                }
            }
            .sheet(isPresented: $showItemCreationView) {
                ItemCreationView()
            }
            
        } else {
            TabView(selection: $selection) {
                // Home Tab
                InventoryView(showItemCreationView: $showItemCreationView)
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
        }
    }
    
    private func addItem() {
        showItemCreationView = true
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self)
}

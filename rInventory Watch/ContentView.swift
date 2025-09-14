//
//  ContentView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 8/11/25.
//

import SwiftUI
import SwiftData
           
// Helper to determine if Liquid Glass design is available
let usesLiquidGlass: Bool = {
    if #available(watchOS 26.0, *) {
        return true
    } else {
        return false
    }
}()

struct ContentView: View {
    @ObservedObject var syncEngine: CloudKitSyncEngine
    @State var tabSelection: Int = 0
    
    var body: some View {
        TabView(selection: $tabSelection) {
            InventoryView(syncEngine: syncEngine)
                .disabled(tabSelection != 0)
                .tabItem {
                    Label("Inventory", systemImage: "list.bullet")
                }
                .tag(0) // Tag for Home Tab
            
            SearchView()
                .disabled(tabSelection != 1)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1) // Tag for Search Tab
        }
    }
}

#Preview {
    let tempContainer = try! ModelContainer(for: Item.self, Location.self, Category.self)
    let engine = CloudKitSyncEngine(modelContext: tempContainer.mainContext)
    ContentView(syncEngine: engine)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

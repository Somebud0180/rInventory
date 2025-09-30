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
    @SceneStorage("ContentView.tabSelection") var tabSelection: Int = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $tabSelection) {
                InventoryView(isActive: tabSelection == 0)
                    .tabItem {
                        Label("Inventory", systemImage: "list.bullet")
                    }
                    .tag(0) // Tag for Home Tab
                
                SearchView(isActive: tabSelection == 1)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1) // Tag for Search Tab
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .font(.body)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

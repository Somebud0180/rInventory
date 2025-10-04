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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var selectedSortType: SortType = .order
    @State private var showSortPicker: Bool = false
    @State var tabSelection: Int = 0
    
    var body: some View {
        NavigationStack {
            tabView()
                .navigationTitle(tabSelection == 0 ? "rInventory" : "Search")
                .toolbar {
                    if tabSelection == 0 {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { showSortPicker = true }) {
                                Image(systemName: sortSymbol(for: selectedSortType))
                                    .font(.body)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .font(.body)
                        }
                    }
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .background {
                        try? modelContext.save()
                    }
                }
                .fullScreenCover(isPresented: $showSortPicker) {
                    SortPickerView(selectedSortType: $selectedSortType)
                }
        }
    }
    
    private func tabView() -> some View {
        if #available(watchOS 11.0, *) {
            return TabView(selection: $tabSelection) {
                // Home Tab
                Tab("Home", systemImage: "house", value: 0) {
                    InventoryView(selectedSortType: $selectedSortType, showSortPicker: $showSortPicker, isActive: tabSelection == 0)
                        .disabled(tabSelection != 0)
                }
                
                // Search Tab
                Tab("Search", systemImage: "magnifyingglass", value: 1, role: .search) {
                    SearchView(isActive: tabSelection == 1)
                        .disabled(tabSelection != 1)
                }
            }
        } else {
            return TabView(selection: $tabSelection) {
                // Home Tab
                InventoryView(selectedSortType: $selectedSortType, showSortPicker: $showSortPicker, isActive: tabSelection == 0)
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0) // Tag for Home Tab
                    .disabled(tabSelection != 0)
                
                // Search Tab
                SearchView(isActive: tabSelection == 1)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1) // Tag for Search Tab
                    .disabled(tabSelection != 1)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

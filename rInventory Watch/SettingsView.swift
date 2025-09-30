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
    @EnvironmentObject var appDefaults: AppDefaults
    
    var body: some View {
        NavigationStack {
            Form {
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    
    var body: some View {
        List {
            ForEach(categories, id: \.id) { category in
                Button(action: {
                    // Toggle visibility for just this category
                    category.displayInRow.toggle()
                }) {
                    HStack {
                        Text(category.name)
                        Spacer()
                        Image(systemName: category.displayInRow ? "checkmark.circle.fill" : "circle")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .navigationTitle("Categories")
    }
}

struct LocationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Location.sortOrder, order: .forward) private var locations: [Location]
    
    var body: some View {
        List {
            ForEach(locations, id: \.id) { location in
                Button(action: {
                    // Toggle visibility for just this location
                    location.displayInRow.toggle()
                }) {
                    HStack {
                        Text(location.name)
                        Spacer()
                        Image(systemName: location.displayInRow ? "checkmark.circle.fill" : "circle")
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
}

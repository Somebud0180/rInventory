//
//  InventoryRowSortView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/19/25.
//
//  Contains the view for sorting inventory rows.

import SwiftUI
import SwiftData

struct InventoryRowSortView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Query location and category, filtered by sort order
    @Query(sort: \Location.sortOrder, order: .forward) private var locations: [Location]
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    
    // Configurations
    @State private var viewAs: String = "Rows"
    @State private var showRecentlyAdded: Bool = true
    @State private var showCategories: Bool = true
    @State private var showLocations: Bool = true
    
    var body: some View {
        NavigationStack {
            List {
                Section("Sort Options") {
                    Picker("View As", selection: $viewAs) {
                        Text("Rows").tag("Rows")
                        Text("Grid").tag("Grid")
                    }.pickerStyle(.segmented)
                    
                    Toggle("Show Recently Added", isOn: $showRecentlyAdded)
                    
                    if viewAs == "Rows" {
                        Toggle("Show Categories", isOn: $showCategories)
                        Toggle("Show Locations", isOn: $showLocations)
                    }
                }
                .animation(.interactiveSpring, value: viewAs)
                
                Section("Sort Categories") {
                    ForEach(categories, id: \.id) { category in
                        HStack {
                            Button(action: {
                                // Toggle visibility
                                category.displayInRow.toggle()
                                try? modelContext.save()
                            }) {
                                Image(systemName: category.displayInRow ? "checkmark.circle.fill" : "circle")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(category.displayInRow ? .accentColor : .gray)
                            }
                            if category.name.isEmpty {
                                Text("(Empty Category - ID: \(category.id.uuidString.prefix(8)))")
                                    .foregroundColor(.red)
                                    .italic()
                            } else {
                                Text(category.name)
                            }
                            Spacer()
                            if category.name.isEmpty {
                                Button("Delete") {
                                    modelContext.delete(category)
                                    try? modelContext.save()
                                }
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Add cleanup button
                    Button("Clean Up Empty Categories") {
                        Category.cleanupEmpty(in: modelContext)
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Sort Locations") {
                    ForEach(locations, id: \.id) { location in
                        HStack {
                            Button(action: {
                                // Toggle visibility
                                location.displayInRow.toggle()
                            }) {
                                Image(systemName: location.displayInRow ? "checkmark.circle.fill" : "circle")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(location.displayInRow ? .accentColor : .gray)
                            }
                            Text(location.name)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    InventoryRowSortView()
        .modelContainer(for: [Location.self, Category.self])
}

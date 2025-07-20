//
//  InventorySortView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/19/25.
//
//  Contains the view for sorting inventory rows.

import SwiftUI
import SwiftData

struct InventorySortView: View {
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
    @State private var isCategorySectionExpanded: Bool = true
    @State private var isLocationSectionExpanded: Bool = true
    @State private var isReordering: Bool = false // Track reordering state
    
    var body: some View {
        NavigationStack {
            List {
                sortOptionsSection
                
                if !categories.isEmpty {
                    categorySection
                }
                
                if !locations.isEmpty {
                    locationSection
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Inventory View Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Sections
    private var sortOptionsSection: some View {
        Section("Sort Options") {
            Picker("View As", selection: Binding(
                get: { viewAs },
                set: { newValue in
                    withAnimation(.interactiveSpring) {
                        viewAs = newValue
                    }
                })
            ) {
                Text("Rows").tag("Rows")
                Text("Grid").tag("Grid")
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            
            Toggle("Show Recently Added", isOn: $showRecentlyAdded)
            
            if viewAs == "Rows" {
                Toggle("Show Categories", isOn: $showCategories)
                Toggle("Show Locations", isOn: $showLocations)
            }
        }
    }
    
    private var categorySection: some View {
        Section("Sort Categories", isExpanded: Binding(
            get: { isCategorySectionExpanded },
            set: { newValue in
                withAnimation(.interactiveSpring) {
                    isCategorySectionExpanded = newValue
                }
            })
        ) {
            ForEach(categories, id: \.id) { category in
                HStack {
                    Button(action: {
                        // Toggle visibility
                        withAnimation {
                            category.displayInRow.toggle()
                            try? modelContext.save()
                        }
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
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                }
            }
            .onMove(perform: moveCategory)
        }
    }
    
    private var locationSection: some View {
        Section("Sort Locations", isExpanded: Binding(
            get: { isLocationSectionExpanded },
            set: { newValue in
                withAnimation(.interactiveSpring) {
                    isLocationSectionExpanded = newValue
                }
            })
        ) {
            ForEach(locations, id: \.id) { location in
                HStack {
                    Button(action: {
                        // Toggle visibility
                        withAnimation {
                            location.displayInRow.toggle()
                        }
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
            .onMove(perform: moveLocation)
        }
    }
    
    // MARK: - Move Handlers
    private func moveCategory(from source: IndexSet, to destination: Int) {
        guard !isReordering else { return } // Prevent concurrent reordering
        isReordering = true
        
        var revised = categories
        revised.move(fromOffsets: source, toOffset: destination)
        
        // Batch the updates
        for (index, category) in revised.enumerated() {
            category.sortOrder = index
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving category reorder: \(error)")
        }
        
        // Delay to prevent rapid reordering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isReordering = false
        }
    }
    
    private func moveLocation(from source: IndexSet, to destination: Int) {
        guard !isReordering else { return } // Prevent concurrent reordering
        isReordering = true
        
        var revised = locations
        revised.move(fromOffsets: source, toOffset: destination)
        
        // Batch the updates
        for (index, location) in revised.enumerated() {
            location.sortOrder = index
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving location reorder: \(error)")
        }
        
        // Delay to prevent rapid reordering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isReordering = false
        }
    }
}


#Preview {
    InventorySortView()
        .modelContainer(for: [Location.self, Category.self])
}

//
//  InventoryOptionsView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/19/25.
//
//  Contains the view for configuring the inventory view.

import SwiftUI
import SwiftData

struct InventoryOptionsView: View {
    @EnvironmentObject var appDefaults: AppDefaults
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Query location and category, filtered by sort order
    @Query(sort: \Location.sortOrder, order: .forward) private var locations: [Location]
    @Query(sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    
    // Configurations
    @State private var isCategorySectionExpanded: Bool = true
    @State private var isLocationSectionExpanded: Bool = true
    @State private var isReordering: Bool = false
    @State private var pendingSave: Bool = false
    @State private var categoryToDelete: Category?
    @State private var locationToDelete: Location?
    
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
            .alert("Delete Category?", isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { categoryToDelete = nil }
                Button("Delete", role: .destructive) {
                    categoryToDelete?.deleteCategory(context: modelContext)
                    categoryToDelete = nil
                }
            } message: {
                Text("Deleting \(categoryToDelete?.name ?? "this category") will remove this category from all its items. The items will be kept.")
            }
            .alert("Delete Location?", isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { locationToDelete = nil }
                Button("Delete Location and Items", role: .destructive) {
                    locationToDelete?.deleteLocation(context: modelContext)
                    locationToDelete = nil
                }
            } message: {
                Text("Deleting \(locationToDelete?.name ?? "this location") will permanently delete all items in this location.")
            }
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
            VStack(alignment: .leading) {
                Text("Default Sort By")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Picker("Default Inventory Sort", selection: $appDefaults.defaultInventorySort) {
                    Text("Sort Order").tag(0)
                    Text("Alphabetical").tag(1)
                    Text("Date Added").tag(2)
                }
                .pickerStyle(.segmented)
            }
            .listRowSeparator(.hidden)
            
            VStack(alignment: .leading) {
                Text("View As")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Picker("View As Rows", selection: Binding(
                    get: { appDefaults.showInventoryAsRows },
                    set: { newValue in
                        withAnimation(.smooth) { appDefaults.showInventoryAsRows = newValue }
                    })
                ) {
                    Text("Rows").tag(true)
                    Text("Grid").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .listRowSeparator(.hidden)
            
            VStack(spacing: 12) {
                Toggle("Show Recently Added", isOn: Binding(
                    get: { appDefaults.showRecentlyAdded },
                    set: { newValue in
                        withAnimation(.smooth) { appDefaults.showRecentlyAdded = newValue }
                    })
                ).transition(.opacity)
                
                if appDefaults.showInventoryAsRows {
                    Group {
                        Divider()
                        
                        Toggle("Show Categories", isOn: Binding(
                            get: { appDefaults.showCategories },
                            set: { newValue in
                                withAnimation(.smooth) { appDefaults.showCategories = newValue }
                            })
                        )
                        
                        Divider()
                        
                        Toggle("Show Locations", isOn: Binding(
                            get: { appDefaults.showLocations },
                            set: { newValue in
                                withAnimation(.smooth) { appDefaults.showLocations = newValue }
                            })
                        )
                    }.transition(.opacity)
                } else {
                    Group {
                        Divider()
                        
                        Toggle("Show Hidden Categories", isOn: Binding(
                            get: { appDefaults.showHiddenCategoriesInGrid },
                            set: { newValue in
                                withAnimation(.smooth) { appDefaults.showHiddenCategoriesInGrid = newValue }
                            })
                        )
                        
                        Divider()
                        
                        Toggle("Show Hidden Locations", isOn: Binding(
                            get: { appDefaults.showHiddenLocationsInGrid },
                            set: { newValue in
                                withAnimation(.smooth) { appDefaults.showHiddenLocationsInGrid = newValue }
                            })
                        )
                    }.transition(.opacity)
                }
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
                            SyncPersistence.saveReporting(modelContext)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        categoryToDelete = category
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

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
                            SyncPersistence.saveReporting(modelContext)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        locationToDelete = location
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                }
            }
            .onMove(perform: moveLocation)
        }
    }
    
    // MARK: - Move Handlers
    private func moveCategory(from source: IndexSet, to destination: Int) {
        // Prevent overlapping reorder operations
        guard !isReordering else { return }
        
        // Set reordering state
        isReordering = true
        
        // Perform the array reordering first
        var revised = categories
        revised.move(fromOffsets: source, toOffset: destination)
        
        // Update sort orders with animation - wrap the entire batch
        withAnimation(.smooth(duration: 0.3)) {
            for (index, category) in revised.enumerated() {
                category.sortOrder = index
            }
        }
        
        // Save after animation completes, with debouncing
        SyncPersistence.saveReporting(modelContext)
        
        // Reset reordering state after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isReordering = false
        }
    }
    
    private func moveLocation(from source: IndexSet, to destination: Int) {
        // Prevent overlapping reorder operations
        guard !isReordering else { return }
        
        // Set reordering state
        isReordering = true
        
        // Perform the array reordering first
        var revised = locations
        revised.move(fromOffsets: source, toOffset: destination)
        
        // Update sort orders with animation
        withAnimation(.smooth(duration: 0.3)) {
            for (index, location) in revised.enumerated() {
                location.sortOrder = index
            }
        }
        
        // Save after animation completes, with debouncing
        SyncPersistence.saveReporting(modelContext)
        
        // Reset reordering state after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isReordering = false
        }
    }
    
}

#Preview {
    InventoryOptionsView()
        .modelContainer(for: [Location.self, Category.self])
}


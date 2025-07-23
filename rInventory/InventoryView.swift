//
//  InventoryView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view for displaying and managing inventory items, with sorting and filtering capabilities.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation
import Combine

let inventoryActivityType = "com.lagera.Inventory.viewingInventory"
let rowColumns = [
    GridItem(.adaptive(minimum: 500), spacing: 16)
]

/// Represents a unique identifier for an item that can be transferred between devices.
struct ItemIdentifier: Transferable {
    let id: UUID
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .data) { identifier in
            identifier.id.uuidString.data(using: .utf8) ?? Data()
        } importing: { data in
            guard let string = String(data: data, encoding: .utf8),
                  let uuid = UUID(uuidString: string) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ItemIdentifier(id: uuid)
        }
    }
}

struct InventoryView: View {
    @EnvironmentObject private var appDefaults: AppDefaults
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query(filter: #Predicate<Location> { $0.displayInRow == true }, sort: \Location.sortOrder, order: .forward) private var locations: [Location]
    @Query(filter: #Predicate<Category> { $0.displayInRow == true }, sort: \Category.sortOrder, order: .forward) private var categories: [Category]
    
    @StateObject var syncEngine: CloudKitSyncEngine
    @Binding var showItemCreationView: Bool
    @Binding var showItemView: Bool
    @Binding var selectedItem: Item?
    @State var isActive: Bool
    
    @StateObject private var viewModel = InventoryViewModel()
    @State private var showInventoryOptionsView: Bool = false
    @State private var showInventoryRowView: Bool = false
    @State private var showingSyncError = false
    @State private var showingSyncSpinner = false
    
    private var errorMessage: String {
        if case .error(let error) = syncEngine.syncState {
            return error
        }
        return ""
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                headerSection
                    .padding(.leading, 4)
                    .padding(.bottom, 16)
                
                if items.isEmpty {
                    emptyItemsView
                } else {
                    VStack(spacing: 16) {
                        if appDefaults.showRecentlyAdded {
                            LazyVGrid(columns: rowColumns, spacing: 16) {
                                inventoryRow(predicate: "RecentlyAdded", itemAmount: items.count, title: "Recently Added", showCategoryPicker: false, showSortPicker: false)
                                inventoryRow(title: "All Items", showCategoryPicker: true, showSortPicker: true)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        } else {
                            inventoryRow(itemAmount: 7, title: "All Items", showCategoryPicker: true, showSortPicker: true)
                                .transition(.opacity)
                        }
                        
                        // Categories section
                        if !categories.isEmpty && appDefaults.showCategories {
                            VStack(alignment: .leading, spacing: 16) {
                                if !categories.isEmpty {
                                    Text("Categories")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 8)
                                        .padding(.bottom, -8)
                                    
                                    LazyVGrid(columns: rowColumns, spacing: 16) {
                                        ForEach(categories, id: \ .id) { category in
                                            inventoryRow(predicate: "Category: \(category.id)", title: category.name, showSortPicker: true)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Locations section
                        if !locations.isEmpty && appDefaults.showLocations {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Locations")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                                    .padding(.bottom, -8)
                                
                                LazyVGrid(columns: rowColumns, spacing: 16) {
                                    ForEach(locations, id: \ .id) { location in
                                        inventoryRow(predicate: "Location: \(location.id)", title: location.name, color: location.color, showCategoryPicker: true, showSortPicker: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollDisabled(items.isEmpty)
            .navigationTitle("rInventory")
            .navigationBarTitleDisplayMode(.large)
            .padding(.horizontal, 16)
            .sheet(isPresented: $showInventoryOptionsView, onDismiss: { Task { await syncEngine.manualSync() } }) {
                InventoryOptionsView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showingSyncSpinner {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showItemCreationView = true }) {
                        Label("Add", systemImage: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showInventoryOptionsView = true }) {
                        Label("Edit", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.titleOnly)
                    }
                }
            }
            .refreshable {
                await syncEngine.manualSync()
            }
            .onAppear {
                initializeSortOrders()
                // Re-initialize sync engine with current modelContext if needed
                if syncEngine.modelContext != modelContext {
                    syncEngine.updateModelContext(modelContext)
                }
            }
            .onChange(of: syncEngine.syncState) {
                if case .error = syncEngine.syncState {
                    showingSyncError = true
                }
                // Show spinner while syncing, hide when done
                showingSyncSpinner = syncEngine.syncState == .syncing
            }
            .alert("Sync Error", isPresented: $showingSyncError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .userActivity(inventoryActivityType, isActive: isActive) { activity in
            updateUserActivity(activity)
        }
    }
    
    /// Returns a header section with a greeting based on the time of day.
    private var headerSection: some View {
        Text(greetingTime())
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -10)
    }
    
    private var emptyItemsView: some View {
        Group {
            Group {
                Text("Add a new item by pressing ") + Text(Image(systemName: "plus.circle")) + Text(" in the top-right corner.")
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.gray)
            .font(.subheadline)
            .padding(12)
            
            
            // Pseudo-grid to display app feel
            VStack(spacing: 16) {
                LazyVGrid(columns: rowColumns, spacing: 16) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8.0)
                                .fill(Color.gray.opacity(0.8))
                                .frame(width: 100, height: 16)
                                .padding(.bottom, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(0..<5, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 25.0)
                                            .fill(Color.gray.opacity(0.8))
                                            .aspectRatio(1.0, contentMode: .fit)
                                            .frame(minWidth: 150, maxWidth: 300, minHeight: 150, maxHeight: 300)
                                    }
                                }
                            }
                            .scrollDisabled(true)
                            .scrollClipDisabled()
                        }
                        .padding(.top, 4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)
                                .foregroundStyle(.gray.opacity(colorScheme == .light ? 0.1 : 0.25)))
                        .clipShape(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius))
                    }
                }
            }
            .mask {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.white.opacity(0.8), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.5)
                }
            }
        }
    }
    
    /// Returns a row of inventory items with a navigation title.
    /// - Parameters:
    /// - predicate: A predicate to filter items in the row. (RecentlyAdded, Category: Category.id, Location: Location.id)
    /// - itemAmount: The maximum number of items to display (default is 4).
    /// - title: The title for the row.
    /// - color: The color theme for the row.
    /// - showCategoryPicker: Whether to show the category picker.
    /// - showSortPicker: Whether to show the sort picker.
    private func inventoryRow(predicate: String? = nil, itemAmount: Int = 4, title: String, color: Color = Color.gray, showCategoryPicker: Bool = false, showSortPicker: Bool = false) -> some View {
        let filteredItems = filteredItems(for: predicate)
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    InventoryGridView(title: title, predicate: predicate, showCategoryPicker: showCategoryPicker, showSortPicker: showSortPicker, selectedItem: $selectedItem)
                } label: {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }.padding(.leading, 8)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        // Limit to only itemAmount items per row
                        ForEach(filteredItems.prefix(itemAmount), id: \ .id) { item in
                            ItemCard(
                                item: item,
                                colorScheme: colorScheme,
                                showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                                onTap: {
                                    selectedItem = item
                                }
                            )
                            .aspectRatio(1.0, contentMode: .fit)
                            .frame(minWidth: 150, maxWidth: 300, minHeight: 150, maxHeight: 300)
                        }
                        
                        if filteredItems.count < itemAmount {
                            Spacer()
                        } else if filteredItems.count > itemAmount {
                            NavigationLink {
                                InventoryGridView(title: title, predicate: predicate, showCategoryPicker: showCategoryPicker, showSortPicker: showSortPicker, selectedItem: $selectedItem)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 25.0)
                                        .aspectRatio(contentMode: .fill)
                                        .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    
                                    HStack(spacing: 4) {
                                        Text("View All")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white)
                                    }
                                    .padding(8)
                                }
                                .aspectRatio(1.0, contentMode: .fit)
                                .frame(minWidth: 150, maxWidth: 300, minHeight: 150, maxHeight: 300)
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)
                        .foregroundStyle(color.opacity(colorScheme == .light ? 0.1 : 0.25))
                )
                .clipShape(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius))
        )
    }
    
    /// Filters items based on the given predicate.
    private func filteredItems(for predicate: String?) -> [Item] {
        if let predicate = predicate {
            if predicate == "RecentlyAdded" {
                return items.filter { $0.itemCreationDate > Date().addingTimeInterval(-7 * 24 * 60 * 60) }
            } else if predicate.contains("Category: ") {
                return items.filter {
                    if let catID = $0.category?.id.uuidString {
                        return catID == predicate.replacingOccurrences(of: "Category: ", with: "")
                    }
                    return false
                }
            } else if predicate.contains("Location: ") {
                return items.filter {
                    if let locID = $0.location?.id.uuidString {
                        return locID == predicate.replacingOccurrences(of: "Location: ", with: "")
                    }
                    return false
                }
            }
        }
        return items
    }
    
    /// Initializes sort orders for categories and items if they are not set.
    private func initializeSortOrders() {
        // Initialize category sort orders if there's multiple categories without a sort order
        let categoriesNeedingOrder = categories.filter { $0.sortOrder == 0 }
        if categoriesNeedingOrder.count > 1 {
            for (index, category) in categoriesNeedingOrder.enumerated() {
                category.sortOrder = index
            }
        }
        
        // Initialize location sort orders if there's multiple locations without a sort order
        let locationsNeedingOrder = locations.filter { $0.sortOrder == 0 }
        if locationsNeedingOrder.count > 1 {
            for (index, location) in locationsNeedingOrder.enumerated() {
                location.sortOrder = index
            }
        }
        
        // Initialize item sort orders if there's multiple items without a sort order
        let itemsNeedingOrder = items.filter { $0.sortOrder == 0 }
        if itemsNeedingOrder.count > 1 {
            for (index, item) in itemsNeedingOrder.enumerated() {
                item.sortOrder = index
            }
        }
    }
    
    /// Returns a greeting based on the current time of day.
    private func greetingTime() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning 🌤️"
        case 12..<17:
            return "Good Afternoon ⛅️"
        default:
            return "Good Evening 🌙"
        }
    }
    
    /// Handles the deletion of items from the inventory.
    /// - Parameter offsets: The offsets of the items to delete.
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    /// Updates the user activity with the current category and sort type.
    /// - Parameter activity: The user activity to update.
    private func updateUserActivity(_ activity: NSUserActivity) {
        activity.title = "View Inventory"
        activity.userInfo = ["tabSelection": 0]
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
    }
}

#Preview {
    @Previewable @State var showItemCreationView: Bool = false
    @Previewable @State var showItemView: Bool = false
    @Previewable @State var selectedItem: Item? = nil
    @Previewable @State var isActive: Bool = true
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    InventoryView(syncEngine: syncEngine, showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem, isActive: isActive)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

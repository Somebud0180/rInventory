//
//  InventoryView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view for displaying and managing inventory items, with sorting and filtering capabilities.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation
import Combine

let inventoryActivityType = "ethanj.Inventory.viewingInventory"

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
    @Environment(\.editMode) private var editMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var categories: [Category]
    
    @StateObject var syncEngine: CloudKitSyncEngine
    @Binding var showItemCreationView: Bool
    @Binding var showItemView: Bool
    @Binding var selectedItem: Item?
    @State var isActive: Bool
    
    @StateObject private var viewModel = InventoryViewModel()
    @State private var continuedGridCategory: String? = nil
    @State private var showContinuedGrid: Bool = false
    @State private var categoryMenuPresented = false
    @State private var sortMenuPresented = false
    @State private var draggedItem: Item?
    @State private var showingSyncError = false
    @State private var showingSyncSpinner = false
    
    private var recentlyAddedItems: [Item] {
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return items.lazy.filter { $0.itemCreationDate > cutoffDate }.sorted { $0.itemCreationDate > $1.itemCreationDate }
    }
    
    private var filteredItems: [Item] {
        viewModel.filteredItems(from: items)
    }
    
    var body: some View {
        // Extract error message for sync error alert
        let errorMessage: String = {
            if case .error(let error) = syncEngine.syncState {
                return error
            }
            return ""
        }()
        
        NavigationStack {
            ScrollView {
                headerSection
                    .padding(.leading, 4)
                    .padding(.bottom, 16)
                
                if items.isEmpty {
                    emptyItemsView
                } else {
                    VStack(spacing: 16) {
                        if !recentlyAddedItems.isEmpty {
                            inventoryRow(rowItems: recentlyAddedItems, title: "Recently Added")
                        }
                        
                        inventoryRow(rowItems: items, title: "All Items", showCategoryPicker: true, showSortPicker: true)
                        
                        ForEach(categories, id: \.id) { category in
                            let categoryItems = (category.items ?? []).sorted { $0.sortOrder < $1.sortOrder }
                            if !categoryItems.isEmpty {
                                inventoryRow(rowItems: categoryItems, title: category.name, showSortPicker: true)
                            }
                        }
                    }
                }
            }
            .scrollDisabled(items.isEmpty)
            .scrollClipDisabled(true)
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .padding(.horizontal, 16)
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
                    EditButton()
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
                // If syncing is in progress on appear, show spinner
                showingSyncSpinner = syncEngine.syncState == .syncing
            }
            .onChange(of: editMode?.wrappedValue) {
                if editMode?.wrappedValue == .inactive {
                    viewModel.selectedItemIDs.removeAll()
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
        .fullScreenCover(isPresented: $showContinuedGrid) {
            InventoryGridView(
                title: continuedGridCategory ?? "Inventory",
                itemsGroup: items.filter { $0.category?.name == continuedGridCategory },
                showCategoryPicker: true,
                showSortPicker: true,
                selectedItem: $selectedItem
            )
        }
        .userActivity(inventoryActivityType, isActive: isActive) { activity in
            updateUserActivity(activity)
        }
        .onContinueUserActivity(inventoryGridActivityType) { activity in
            if let category = activity.userInfo?[inventoryGridCategoryKey] as? String {
                continuedGridCategory = category
                showContinuedGrid = true
            }
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
            // A gray square grid to simulate items
            LazyVGrid(columns: itemColumns) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 25.0)
                        .fill(Color.gray.opacity(0.8))
                        .aspectRatio(1.0, contentMode: .fit)
                }
            }
            .mask(
                Rectangle()
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
            )
        }
    }
    
    /// Returns a row of inventory items with a navigation title.
    /// - Parameters:
    /// - items: The array of items to display in the row.
    /// - title: The title for the row.
    private func inventoryRow(rowItems: [Item], title: String, showCategoryPicker: Bool = false, showSortPicker: Bool = false) -> some View {
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    InventoryGridView(title: title, itemsGroup: rowItems, showCategoryPicker: showCategoryPicker, showSortPicker: showSortPicker, selectedItem: $selectedItem)
                } label: {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        // Limit to only 5 items per row
                        ForEach(rowItems.prefix(6), id: \.id) { item in
                            DraggableItemCard(
                                item: item,
                                colorScheme: colorScheme,
                                showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                                draggedItem: $draggedItem,
                                onTap: {
                                    selectedItem = item
                                },
                                onDragChanged: { isDragging in
                                    draggedItem = isDragging ? item : nil
                                },
                                onDrop: { droppedItemId in
                                    handleDrop(items, filteredItems: filteredItems, draggedItem: $draggedItem, droppedItemId: droppedItemId, target: item)
                                },
                                isEditing: editMode?.wrappedValue.isEditing ?? false,
                                isSelected: viewModel.selectedItemIDs.contains(item.id)
                            )
                            .aspectRatio(1.0, contentMode: .fit)
                            .frame(minWidth: 150, maxWidth: 300, minHeight: 150, maxHeight: 300)
                        }
                        
                        if rowItems.count < 6 {
                            Spacer()
                        } else if rowItems.count > 6 {
                            NavigationLink {
                                InventoryGridView(title: title, itemsGroup: rowItems, showCategoryPicker: showCategoryPicker, showSortPicker: showSortPicker, selectedItem: $selectedItem)
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
            }
                .scrollClipDisabled(true)
        )
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

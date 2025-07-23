//
//  InventoryGridView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/13/25.
//

import SwiftUI
import SwiftData

let inventoryGridActivityType = "com.lagera.Inventory.viewingGrid"
let inventoryGridTitleKey = "title"
let inventoryGridPredicateKey = "predicate"
let inventoryGridCategoryKey = "category"
let inventoryGridSortKey = "sort"

struct InventoryGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    
    @Query private var items: [Item]
    
    // Grab Categories from Items
    private var categories: [Category] {
        [Category(name: "All Items")] +
        Array(Set(items.compactMap { $0.category }))
    }
    
    @State var title: String
    @State var predicate: String? = nil
    @State var showCategoryPicker: Bool = false
    @State var showSortPicker: Bool = false
    @Binding var selectedItem: Item?
    @Binding var isInventoryActive: Bool
    @Binding var isInventoryGridActive: Bool
        
    // Generate a Predicate based on the predicate string
    private var filteredItems: [Item] {
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
    
    @StateObject private var viewModel = InventoryViewModel()
    
    // State variable for UI
    @State private var draggedItem: Item? = nil
    @State private var categoryMenuPresented = false
    @State private var sortMenuPresented = false
    
    private var modelFilteredItems: [Item] {
        viewModel.filteredItems(from: filteredItems)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .bottom) {
                    if showCategoryPicker {
                        categoryPicker
                    }
                    Spacer()
                    if showSortPicker {
                        sortPicker
                    }
                }
                
                if modelFilteredItems.isEmpty {
                    Text("No items found")
                        .foregroundColor(.gray)
                        .padding(10)
                } else {
                    inventoryGrid
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if editMode?.wrappedValue.isEditing == true && !viewModel.selectedItemIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        deleteSelectedItems()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onChange(of: editMode?.wrappedValue.isEditing == true) {
            if !(editMode?.wrappedValue.isEditing == true) {
                viewModel.selectedItemIDs.removeAll()
            }
        }
        .onChange(of: isInventoryActive) {
            if isInventoryActive {
                isInventoryGridActive = true
            } else {
                isInventoryGridActive = false
            }
        }
        .onAppear {
            isInventoryGridActive = true
            let sortTypeIndex = AppDefaults.shared.defaultInventorySort
            viewModel.selectedSortType =
            ([SortType.order, .alphabetical, .dateModified].indices.contains(sortTypeIndex) ? [SortType.order, .alphabetical, .dateModified][sortTypeIndex] : .order)
        }
        .userActivity(inventoryGridActivityType, isActive: isInventoryGridActive) { activity in
            updateUserActivity(activity)
        }
    }
    
    private var inventoryGrid: some View {
        VStack {
            LazyVGrid(columns: itemColumns) {
                ForEach(modelFilteredItems, id: \.id) { item in
                    DraggableItemCard(
                        item: item,
                        colorScheme: colorScheme,
                        showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                        draggedItem: $draggedItem,
                        onTap: {
                            if editMode?.wrappedValue.isEditing == true {
                                if viewModel.selectedItemIDs.contains(item.id) {
                                    viewModel.selectedItemIDs.remove(item.id)
                                } else {
                                    viewModel.selectedItemIDs.insert(item.id)
                                }
                            } else {
                                selectedItem = item
                            }
                        },
                        onDragChanged: { isDragging in
                            draggedItem = isDragging ? item : nil
                        },
                        onDrop: { droppedItemId in
                            handleDrop(items, filteredItems: modelFilteredItems, draggedItem: $draggedItem, droppedItemId: droppedItemId, target: item)
                        },
                        isEditing: editMode?.wrappedValue.isEditing ?? false,
                        isSelected: editMode?.wrappedValue.isEditing == true && viewModel.selectedItemIDs.contains(item.id)
                    )
                }
            }
            Spacer()
        }
    }
    
    /// Returns a category picker menu for selecting inventory categories.
    private var categoryPicker: some View {
        InventoryViewModel.categoryPicker(
            selectedCategory: viewModel.selectedCategory,
            categories: categories,
            menuPresented: $categoryMenuPresented
        ) { selected in
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.selectedCategory = selected
            }
        }
    }
    
    /// Returns a sort picker menu for selecting how to sort inventory items.
    private var sortPicker: some View {
        InventoryViewModel.sortPicker(
            selectedSortType: viewModel.selectedSortType,
            menuPresented: $sortMenuPresented
        ) { selected in
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.selectedSortType = selected
            }
        }
    }
    
    private func deleteSelectedItems() {
        viewModel.deleteSelectedItems(allItems: items, modelContext: modelContext)
    }
    
    private func updateUserActivity(_ activity: NSUserActivity) {
        var userInfo: [String: Any] = [
            inventoryGridPredicateKey: predicate ?? "",
            inventoryGridTitleKey: title
        ]
        if showCategoryPicker {
            userInfo[inventoryGridCategoryKey] = viewModel.selectedCategory
        }
        if showSortPicker {
            userInfo[inventoryGridSortKey] = viewModel.selectedSortType.rawValue
        }
        
        activity.title = "View \(title)"
        activity.addUserInfoEntries(from: userInfo)
        activity.userInfo = ["tabSelection": 0]
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
    }
}

#Preview {
    @Previewable @State var title: String = "All Items"
    @Previewable @State var selectedItem: Item? = nil
    @Previewable @State var isInventoryActive: Bool = true
    @Previewable @State var isInventoryGridActive: Bool = true
    
    InventoryGridView(title: title, selectedItem: $selectedItem, isInventoryActive: $isInventoryActive, isInventoryGridActive: $isInventoryGridActive)
}

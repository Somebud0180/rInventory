//
//  InventoryGridView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/13/25.
//

import SwiftUI
import SwiftData

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
    
    var title: String
    var itemsGroup: [Item]
    var showCategoryPicker: Bool = false
    var showSortPicker: Bool = false
    @Binding var selectedItem: Item?
    
    @StateObject private var viewModel = InventoryViewModel()
    
    // State variable for UI
    @State private var draggedItem: Item? = nil
    @State private var categoryMenuPresented = false
    @State private var sortMenuPresented = false
    
    private var filteredItems: [Item] {
        viewModel.filteredItems(from: itemsGroup)
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
            
                inventoryGrid
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
    }
    
    private var inventoryGrid: some View {
            VStack {
                LazyVGrid(columns: itemColumns) {
                    ForEach(filteredItems, id: \.id) { item in
                        DraggableItemCard(
                            item: item,
                            colorScheme: colorScheme,
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
                                handleDrop(items, filteredItems: itemsGroup, draggedItem: $draggedItem, droppedItemId: droppedItemId, target: item)
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
}

#Preview {
    @Previewable @State var title: String = "All Items"
    @Previewable @State var itemsGroup: [Item] = [
        Item(name: "Item 1", quantity: 0, location: Location(name: "Location 1"), category: Category(name: "Category 1")),
        Item(name: "Item 2", quantity: 0, location: Location(name: "Location 2"), category: Category(name: "Category 2")),
        Item(name: "Item 3", quantity: 0, location: Location(name: "Location 3"), category: Category(name: "Category 3"))
    ]
    @Previewable @State var selectedItem: Item? = nil
    
    InventoryGridView(title: title, itemsGroup: itemsGroup, selectedItem: $selectedItem)
}


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
    
    var title: String
    var itemsGroup: [Item]
    @Binding var selectedItem: Item?
    
    @StateObject private var viewModel = InventoryViewModel()
    
    // State variable for UI
    @State private var draggedItem: Item? = nil
    
    var body: some View {
        NavigationStack {
            inventoryGrid
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
        ScrollView {
            VStack {
                LazyVGrid(columns: itemColumns) {
                    ForEach(itemsGroup, id: \.id) { item in
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
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func deleteSelectedItems() {
        viewModel.deleteSelectedItems(allItems: items, modelContext: modelContext)
    }
}

#Preview {
    @Previewable @State var title: String = "My Inventory"
    @Previewable @State var itemsGroup: [Item] = [
        Item(name: "Item 1", quantity: 0, location: Location(name: "Location 1"), category: Category(name: "Category 1")),
        Item(name: "Item 2", quantity: 0, location: Location(name: "Location 2"), category: Category(name: "Category 2")),
        Item(name: "Item 3", quantity: 0, location: Location(name: "Location 3"), category: Category(name: "Category 3"))
    ]
    @Previewable @State var selectedItem: Item? = nil
    
    InventoryGridView(title: title, itemsGroup: itemsGroup, selectedItem: $selectedItem)
}


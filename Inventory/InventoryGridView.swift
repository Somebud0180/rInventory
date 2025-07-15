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
    
    // State variables for UI
    @State private var selectedSortType: SortType = .order
    @State private var draggedItem: Item? = nil
    @State private var selectedItemIDs: Set<UUID> = []
    
    private var filteredItems: [Item] {
        let filtered = itemsGroup
        switch selectedSortType {
        case .order:
            return filtered.sorted(by: { $0.sortOrder < $1.sortOrder })
        case .alphabetical:
            return filtered.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .dateModified:
            return filtered.sorted(by: { ($0.modifiedDate) > ($1.modifiedDate) })
        }
    }
    
    var body: some View {
        NavigationStack {
            inventoryGrid
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            if editMode?.wrappedValue.isEditing == true && !selectedItemIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        deleteSelectedItems()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
    
    private var inventoryGrid: some View {
        ScrollView {
            VStack {
                LazyVGrid(columns: itemColumns) {
                    ForEach(filteredItems, id: \.id) { item in
                        DraggableItemCard(
                            item: item,
                            colorScheme: colorScheme,
                            draggedItem: $draggedItem,
                            onTap: {
                                if editMode?.wrappedValue.isEditing == true {
                                    if selectedItemIDs.contains(item.id) {
                                        selectedItemIDs.remove(item.id)
                                    } else {
                                        selectedItemIDs.insert(item.id)
                                    }
                                } else {
                                    selectedItem = item
                                }
                            },
                            onDragChanged: { isDragging in
                                draggedItem = isDragging ? item : nil
                            },
                            onDrop: { droppedItemId in
                                handleDrop(items, filteredItems: filteredItems, draggedItem: $draggedItem, droppedItemId: droppedItemId, target: item)
                            },
                            isEditing: editMode?.wrappedValue.isEditing ?? false,
                            isSelected: editMode?.wrappedValue.isEditing == true && selectedItemIDs.contains(item.id)
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
        let itemsToDelete = items.filter { selectedItemIDs.contains($0.id) }
        for item in itemsToDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            // handle error as needed
        }
        selectedItemIDs.removeAll()
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

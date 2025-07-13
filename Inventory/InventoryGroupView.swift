//
//  InventoryGroupView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/13/25.
//

import SwiftUI
import SwiftData

struct InventoryGroupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var items: [Item]
    
    var title: String
    var itemsGroup: [Item]
    @Binding var selectedItem: Item?
    
    @State private var selectedSortType: SortType = .order
    @State private var draggedItem: Item? = nil
    
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 16)
    ]
    
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
    }
    
    private var inventoryGrid: some View {
        ScrollView {
            VStack {
                LazyVGrid(columns: columns) {
                    ForEach(filteredItems, id: \.id) { item in
                        ItemDraggableGridCard(
                            item: item,
                            colorScheme: colorScheme,
                            draggedItem: $draggedItem,
                            onTap: {
                                selectedItem = item
                            },
                            onDragChanged: { isDragging in
                                draggedItem = isDragging ? item : nil
                            },
                            onDrop: { droppedItemId in
                                handleDrop(items, filteredItems: filteredItems, draggedItem: $draggedItem, droppedItemId: droppedItemId, target: item)
                            }
                        )
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    InventoryGroupView(title: title, itemsGroup: itemsGroup, selectedItem: $selectedItem)
}

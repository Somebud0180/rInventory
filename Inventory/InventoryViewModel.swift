//
//  InventoryViewModel.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Centralizes shared inventory logic such as sorting, selection, and deletion.

import SwiftUI
import SwiftData
import Combine

enum SortType: String, CaseIterable {
    case order = "Order"
    case alphabetical = "Alphabetical"
    case dateModified = "Date Modified"
}

let itemColumns = [
    GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 16)
]

class InventoryViewModel: ObservableObject {
    @Published var selectedSortType: SortType = .order
    @Published var selectedCategory: String = "My Inventory"
    @Published var selectedItemIDs: Set<UUID> = []
    
    // Provide sorting for any provided item array
    func filteredItems(from items: [Item]) -> [Item] {
        switch selectedSortType {
        case .order:
            return items.sorted(by: { $0.sortOrder < $1.sortOrder })
        case .alphabetical:
            return items.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .dateModified:
            return items.sorted(by: { ($0.modifiedDate) > ($1.modifiedDate) })
        }
    }
    
    func deleteSelectedItems(allItems: [Item], modelContext: ModelContext) {
        let itemsToDelete = allItems.filter { selectedItemIDs.contains($0.id) }
        for item in itemsToDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete items: \(error.localizedDescription)")
        }
        selectedItemIDs.removeAll()
    }
    
    func clearSelection() {
        selectedItemIDs.removeAll()
    }
}


//
//  ItemGridView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/27/25.
//

import SwiftUI

/// A reusable grid component for displaying items consistently across the app
struct ItemGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let items: [Item]
    let showCounterForSingleItems: Bool
    let onItemSelected: (Item) -> Void
    @Binding var showItemView: Bool
    var onItemAppear: ((Item) -> Void)? = nil
    var onItemDisappear: ((Item) -> Void)? = nil
    
    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            if items.isEmpty {
                Text("No items found")
                    .foregroundColor(.gray)
                    .padding(5)
            } else {
                ForEach(items, id: \.id) { item in
                    ItemCard(
                        item: item,
                        colorScheme: colorScheme,
                        showCounterForSingleItems: showCounterForSingleItems,
                        onTap: {
                            onItemSelected(item)
                            showItemView = true
                        }
                    )
                    .onAppear {
                        onItemAppear?(item)
                    }
                    .onDisappear {
                        onItemDisappear?(item)
                    }
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                }
            }
        }
    }
}

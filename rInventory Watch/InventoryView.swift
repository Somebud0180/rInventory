//
//  InventoryView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/11/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

let gridColumns = [
    GridItem(.adaptive(minimum: 80), spacing: 10)
]

struct InventoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject private var appDefaults: AppDefaults
    @Query private var items: [Item]
    
    @State private var selectedItem: Item? = nil
    @State private var showItemView: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyItemsView
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        if #available(watchOS 26.0, *) {
                            GlassEffectContainer {
                                ForEach(items) { item in
                                    ItemCard(item: item, colorScheme: colorScheme, onTap: {
                                        selectedItem = item
                                        showItemView = true
                                    })
                                    .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                                }
                            }
                        } else {
                            ForEach(items) { item in
                                ItemCard(item: item, colorScheme: colorScheme, onTap: {
                                    selectedItem = item
                                    showItemView = true
                                })
                                .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                            }
                        }
                    }
                }
            }
            .navigationTitle("rInventory")
            .navigationBarTitleDisplayMode(.large)
            .scrollDisabled(items.isEmpty)
            .fullScreenCover(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                if let selectedItem {
                    ItemView(item: bindingForItem(selectedItem, items))
                        .transition(.blurReplace)
                } else {
                    ProgressView("Loading item...")
                }
            }
        }
    }
    
    private var emptyItemsView: some View {
        Group {
            Text("You don't have any items yet. Create new items on your iPhone or iPad.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .font(.subheadline)
                .padding(4)
            
            Spacer(minLength: 10)
            
            // Pseudo-grid to display app feel
            VStack(spacing: 10) {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)
                            .fill(Color.gray.opacity(0.8))
                            .aspectRatio(1.0, contentMode: .fit)
                            .frame(minWidth: 80, maxWidth: 160, minHeight: 80, maxHeight: 160)
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
                    .frame(height: geo.size.height * 0.9)
                }
            }
        }
    }
}

func bindingForItem(_ item: Item, _ items: [Item]) -> Binding<Item> {
    return Binding(
        get: {
            // Fetch the item from the model context
            if let fetchedItem = items.first(where: { $0.id == item.id }) {
                return fetchedItem
            }
            return item
        },
        set: { newValue in
            // Changes are automatically persisted through SwiftData's model context
            // No explicit save needed as SwiftData handles this automatically
        }
    )
}

#Preview {
    InventoryView()
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

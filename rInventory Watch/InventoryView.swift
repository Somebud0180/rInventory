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

enum SortType: String, CaseIterable {
    case order = "Order"
    case alphabetical = "Alphabetical"
    case dateModified = "Date Modified"
}

let gridColumns = [
    GridItem(.adaptive(minimum: 80), spacing: 10)
]

struct InventoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject private var appDefaults: AppDefaults
    @Query private var allItems: [Item]
    
    @State private var selectedItem: Item? = nil
    @State private var showItemView: Bool = false
    
    @State private var selectedSortType: SortType = .order
    @State private var sortMenuPresented: Bool = false
    
    @State private var showSortPicker = false
    
    // Optimize data handling by limiting the number of items processed
    private var items: [Item] {
        let filteredItems: [Item]
        switch selectedSortType {
        case .order:
            filteredItems = allItems.sorted(by: { $0.sortOrder < $1.sortOrder })
        case .alphabetical:
            filteredItems = allItems.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .dateModified:
            filteredItems = allItems.sorted(by: { $0.itemCreationDate > $1.itemCreationDate }).filter( { $0.itemCreationDate > Date().addingTimeInterval(-7 * 24 * 60 * 60) })
        }
        return filteredItems
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyItemsView
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(items) { item in
                            ItemCard(item: item, colorScheme: colorScheme, onTap: {
                                selectedItem = item
                                showItemView = true
                            })
                            .id(item.id) // Add unique ID to improve rendering performance
                            .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                        }
                    }
                }
            }
            .navigationTitle("rInventory")
            .scrollDisabled(items.isEmpty)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSortPicker = true }) {
                        Image(systemName: selectedSortType == .order ? "line.3.horizontal.decrease" :
                                selectedSortType == .alphabetical ? "textformat.abc" :
                                "calendar")
                        .font(.body)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
            }
            .fullScreenCover(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                if let selectedItem {
                    ItemView(item: bindingForItem(selectedItem, items))
                        .transition(.blurReplace)
                } else {
                    ProgressView("Loading item...")
                }
            }
            .sheet(isPresented: $showSortPicker) {
                VStack {
                    Text("Sort Items By")
                        .font(.headline)
                        .padding(.top)
                    List {
                        ForEach(SortType.allCases, id: \.self) { sort in
                            Button(action: {
                                selectedSortType = sort
                                showSortPicker = false
                            }) {
                                HStack {
                                    Image(systemName: sort == .order ? "line.3.horizontal.decrease" :
                                            sort == .alphabetical ? "textformat.abc" :
                                            "calendar")
                                    .font(.body)
                                    Text(sort.rawValue)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if selectedSortType == sort {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
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

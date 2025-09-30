//
//  InventoryView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/11/25.
//

import SwiftUI
import SwiftData

enum SortType: String, CaseIterable {
    case order = "Order"
    case alphabetical = "Alphabetical"
    case dateModified = "Date Modified"
    case recentlyAdded = "Recently Added"
}

let gridColumns = [
    GridItem(.adaptive(minimum: 80), spacing: 10)
]

struct SortPickerView: View {
    @EnvironmentObject private var appDefaults: AppDefaults
    @Binding var selectedSortType: SortType
    @Binding var showSortPicker: Bool
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SortType.allCases, id: \.self) { sort in
                    Button(action: {
                        selectedSortType = sort
                        appDefaults.defaultInventorySort = SortType.allCases.firstIndex(of: sort) ?? 0
                        showSortPicker = false
                    }) {
                        HStack {
                            Image(systemName: sortSymbol(for: sort))
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
            .navigationTitle("Sort Items By")
        }
    }
}

struct InventoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject private var appDefaults: AppDefaults
    @Query private var items: [Item]
    
    @State var isActive: Bool
    
    @State private var selectedItem: Item? = nil
    @State private var showItemView: Bool = false
    @State private var showSortPicker = false
    @State private var selectedSortType: SortType = .order
    
    // State for image prefetching
    @State private var visibleItemIDs = Set<UUID>()
    @State private var prefetchingEnabled = true
    private let prefetchBatchSize = 6 // Smaller batch size for watch
    
    private var filteredItems: [Item] {
        let filteredItems: [Item]
        switch selectedSortType {
        case .order:
            filteredItems = items.sorted(by: { $0.sortOrder < $1.sortOrder })
        case .alphabetical:
            filteredItems = items.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .dateModified:
            filteredItems = items.sorted(by: { ($0.modifiedDate) > ($1.modifiedDate) })
        case .recentlyAdded:
            filteredItems = items.sorted(by: { ($0.itemCreationDate) > ($1.itemCreationDate) }).filter { $0.itemCreationDate > Date().addingTimeInterval(-7 * 24 * 60 * 60) }
        }
        return filteredItems
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyItemsView
                } else {
                    let upcomingItems = calculateUpcomingItems(filteredItems, visibleItemIDs: visibleItemIDs, prefetchBatchSize: prefetchBatchSize)
                    
                    ItemGridView(
                        items: filteredItems,
                        showCounterForSingleItems: appDefaults.showCounterForSingleItems,
                        onItemSelected: { item in
                            selectedItem = item
                            showItemView = true
                        },
                        showItemView: $showItemView,
                        onItemAppear: { item in
                            if prefetchingEnabled {
                                visibleItemIDs.insert(item.id)
                            }
                        },
                        onItemDisappear: { item in
                            if prefetchingEnabled {
                                visibleItemIDs.remove(item.id)
                            }
                        }
                    )
                    .prefetchImages(
                        for: filteredItems.filter { visibleItemIDs.contains($0.id) },
                        upcomingItems: upcomingItems,
                        imageDataProvider: { item in
                            if case .image(let imageData) = item.getBackgroundType() {
                                return imageData
                            }
                            return nil
                        }
                    )
                }
            }
            .scrollDisabled(items.isEmpty)
            .navigationTitle("rInventory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSortPicker = true }) {
                        Image(systemName: sortSymbol(for: selectedSortType))
                            .font(.body)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
            }
            .onAppear {
                let sortTypeIndex = AppDefaults.shared.defaultInventorySort
                selectedSortType =
                ([SortType.order, .alphabetical, .dateModified, .recentlyAdded].indices.contains(sortTypeIndex) ? [SortType.order, .alphabetical, .dateModified, .recentlyAdded][sortTypeIndex] : .order)
                
                // Prime prefetching with initial items
                if prefetchingEnabled && !filteredItems.isEmpty {
                    let initialItems = Array(filteredItems.prefix(min(prefetchBatchSize, filteredItems.count)))
                    ItemImagePrefetcher.prefetchImagesForItems(initialItems) { item in
                        if case .image(let imageData) = item.getBackgroundType() {
                            return imageData
                        }
                        return nil
                    }
                }
            }
            .onChange(of: isActive) {
                if !isActive {
                    // Cancel all prefetching when view disappears
                    if prefetchingEnabled {
                        ItemImagePrefetcher.cancelAllPrefetching()
                        visibleItemIDs.removeAll()
                    }
                }
            }
            .fullScreenCover(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                ItemView(item: $selectedItem)
            }
            .sheet(isPresented: $showSortPicker) {
                SortPickerView(selectedSortType: $selectedSortType, showSortPicker: $showSortPicker)
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

func sortSymbol(for sortType: SortType) -> String {
    switch sortType {
    case .order:
        return "line.3.horizontal.decrease"
    case .alphabetical:
        return "textformat.abc"
    case .dateModified:
        return "calendar"
    case .recentlyAdded:
        return "calendar.badge.plus"
    }
}

#Preview {
    @Previewable @State var isActive: Bool = true
    
    InventoryView(isActive: isActive)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

//
//  InventoryView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  Main view for displaying and managing inventory items, with sorting and filtering capabilities.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

let inventoryActivityType = "ethanj.Inventory.viewingInventory"
let inventorySortTypeKey = "sortType"
let inventoryCategoryKey = "category"

/// Enum representing the different sorting options for inventory items.
enum SortType: String, CaseIterable, Identifiable {
    case order = "Order"
    case alphabetical = "A-Z"
    case dateModified = "Date Modified"
    var id: String { rawValue }
}

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

struct InventoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var categories: [Category]
    
    @Binding var showItemCreationView: Bool
    @Binding var showItemView: Bool
    @Binding var selectedItem: Item?
    @State var isActive: Bool
    
    @SceneStorage("InventoryView.selectedSortType") private var selectedSortType: SortType = .order
    @SceneStorage("InventoryView.selectedCategory") private var selectedCategory: String = "My Inventory"
    
    @State private var categoryMenuPresented = false
    @State private var sortMenuPresented = false
    @State private var draggedItem: Item?
    @State private var emptyItem = Item(name: "Create an item", quantity: 1, location: Location(name: "Press the plus button on the top right", color: .white ), category: nil, imageData: nil, symbol: "plus.circle", symbolColor: .white)
    
    private var filteredItems: [Item] {
        let filtered = selectedCategory == "My Inventory" ? items : items.filter { $0.category?.name == selectedCategory }
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
        let recentlyAddedItems = items.filter { $0.modifiedDate > Date().addingTimeInterval(-7 * 24 * 60 * 60) }
        
        NavigationStack {
            ScrollView {
                headerSection
                
                HStack(alignment: .bottom) {
                    categoryPicker
                    Spacer()
                    sortPicker
                }
                
                Spacer(minLength: 30)
                
                inventoryGrid
                
                if !recentlyAddedItems.isEmpty {
                    inventoryRow(items: recentlyAddedItems, title: "Recently Added")
                        .padding(.top, 16)
                }
            }
            .scrollClipDisabled(true)
            .padding(.horizontal, 16)
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showItemCreationView = true }) {
                        Label("Add", systemImage: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .onAppear {
                initializeSortOrders()
            }
        }
        .userActivity(inventoryActivityType, isActive: isActive) { activity in
            updateUserActivity(activity)
        }
        .onContinueUserActivity(inventoryActivityType) { activity in
            if let info = activity.userInfo {
                // Handle case of deleted categories by verifying existence before assignment
                if let cat = info[inventoryCategoryKey] as? String {
                    if categories.contains(where: { $0.name == cat }) {
                        selectedCategory = cat
                    } else {
                        selectedCategory = "My Inventory"
                    }
                }
                // Sort order is only used for restoring UI state, not for system activity
                if let sortRaw = info[inventorySortTypeKey] as? String, let type = SortType(rawValue: sortRaw) {
                    selectedSortType = type
                }
            }
        }
    }
    
    /// Returns a header section with a greeting based on the time of day.
    private var headerSection: some View {
        Text(greetingTime())
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -10)
    }
    
    /// Returns a category picker menu for selecting inventory categories.
    private var categoryPicker: some View {
        Menu {
            Button("My Inventory") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedCategory = "My Inventory"
                }
            }
            ForEach(categories, id: \.name) { category in
                Button(category.name) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedCategory = category.name
                    }
                }
            }
        } label: {
            CategoryPickerLabel(categoryName: selectedCategory, menuPresented: $categoryMenuPresented)
        }
        .background(colorScheme == .light ? .white.opacity(0.01) : .black.opacity(0.01), in: Capsule())
    }
    
    /// A label for the category picker that dynamically adjusts its width based on the category name.
    private struct CategoryPickerLabel: View {
        @Environment(\.colorScheme) private var colorScheme
        let categoryName: String
        @Binding var menuPresented: Bool
        @State private var displayedWidth: CGFloat = 50
        @State private var measuredWidth: CGFloat = 50
        @State private var lastCategoryName: String = ""
        
        init(categoryName: String, menuPresented: Binding<Bool>) {
            self.categoryName = categoryName
            self._menuPresented = menuPresented
            _lastCategoryName = State(initialValue: categoryName)
        }
        
        var body: some View {
            ZStack {
                // Visible label
                HStack {
                    Text(categoryName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: 32)
                .frame(width: displayedWidth)
                .foregroundColor(.primary)
                .background(colorScheme == .light ? .white.opacity(0.01) : .black.opacity(0.01), in: Capsule())
                
                // Hidden label for measurement
                HStack {
                    Text(categoryName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: CategoryWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()
            }
            .onPreferenceChange(CategoryWidthPreferenceKey.self) { newWidth in
                let width = max(newWidth, 50)
                measuredWidth = width
                displayedWidth = measuredWidth
            }
            .onChange(of: categoryName) {
                lastCategoryName = categoryName
                // Wait until menu is closed before expanding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !menuPresented {
                        displayedWidth = measuredWidth
                    }
                }
            }
            .onChange(of: menuPresented) {
                if !menuPresented {
                    displayedWidth = measuredWidth
                }
            }
            .onAppear {
                displayedWidth = measuredWidth
            }
        }
    }
    
    /// Returns a sort picker menu for selecting how to sort inventory items.
    private var sortPicker: some View {
        Menu {
            ForEach(SortType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedSortType = type
                    }
                } label: {
                    Label(type.rawValue, systemImage: symbolName(for: type))
                }
            }
        } label: {
            SortPickerLabel(selectedSortType: selectedSortType, symbolName: symbolName(for: selectedSortType), menuPresented: $sortMenuPresented)
        }
        .adaptiveGlassButton(tintStrength: 0.0)
    }
    
    /// A label for the sort picker that dynamically adjusts its width based on the selected sort type.
    private struct SortPickerLabel: View {
        let selectedSortType: SortType
        let symbolName: String
        @Binding var menuPresented: Bool
        @State private var displayedWidth: CGFloat = 50
        @State private var measuredWidth: CGFloat = 50
        @State private var lastSortType: SortType
        
        init(selectedSortType: SortType, symbolName: String, menuPresented: Binding<Bool>) {
            self.selectedSortType = selectedSortType
            self.symbolName = symbolName
            self._menuPresented = menuPresented
            _lastSortType = State(initialValue: selectedSortType)
        }
        
        var body: some View {
            ZStack {
                // Visible label
                HStack(spacing: 6) {
                    Image(systemName: symbolName)
                        .font(.body)
                    Text(selectedSortType.rawValue)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: displayedWidth)
                .frame(minHeight: 44)
                .foregroundColor(.primary)
                
                // Hidden label for measurement
                HStack(spacing: 6) {
                    Image(systemName: symbolName)
                        .font(.body)
                    Text(selectedSortType.rawValue)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: SortWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()
            }
            .onPreferenceChange(SortWidthPreferenceKey.self) { newWidth in
                let width = max(newWidth, 50)
                measuredWidth = width
                displayedWidth = measuredWidth
            }
            .onChange(of: selectedSortType) {
                lastSortType = selectedSortType
                // Wait until menu is closed before expanding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !menuPresented {
                        displayedWidth = measuredWidth
                    }
                }
            }
            .onChange(of: menuPresented) {
                if !menuPresented {
                    displayedWidth = measuredWidth
                }
            }
            .onAppear {
                displayedWidth = measuredWidth
            }
        }
    }
    
    /// Preference key to measure width of the dynamic category label
    struct CategoryWidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 100
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    /// Preference key to measure width of the dynamic sort label
    struct SortWidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 100
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    /// Returns a grid of inventory items, showing an empty item if there are no items.
    private var inventoryGrid: some View {
        LazyVGrid(columns: itemColumns) {
            if items.isEmpty {
                gridCard(item: emptyItem, colorScheme: colorScheme)
            } else {
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
        }
    }
    
    /// Returns a row of inventory items with a navigation title.
    /// - Parameters:
    /// - items: The array of items to display in the row.
    /// - title: The title for the row.
    private func inventoryRow(items: [Item], title: String) -> some View {
        if items.isEmpty {
            return AnyView(LazyHStack(spacing: 16) {
                gridCard(item: emptyItem, colorScheme: colorScheme)
            })
        } else {
            return AnyView(VStack(alignment: .leading) {
                NavigationLink {
                    InventoryGridView(title: title, itemsGroup: items, selectedItem: $selectedItem)
                    
                } label: {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        // Limit to only 5 items per row
                        ForEach(items.prefix(5), id: \.id) { item in
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
                            .aspectRatio(1.0, contentMode: .fill)
                            .frame(minWidth: 150, maxWidth: 300, minHeight: 150, maxHeight: 300)
                        }
                        
                        if items.count < 5 {
                            Spacer()
                        } else if items.count > 5 {
                            Button(action: {
                                selectedItem = nil
                                showItemView = true
                            }) {
                                gridCard(item: emptyItem, colorScheme: colorScheme)
                                    .overlay(
                                        Text("More...")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .padding(8)
                                            .background(Color.white.opacity(0.7), in: Capsule())
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
                .scrollClipDisabled(true)
                .frame(maxWidth: .infinity)
            )
        }
    }
    
    /// Returns the appropriate symbol name based on the sort type.
    /// - Parameter type: The sort type for which to get the symbol name.
    private func symbolName(for type: SortType) -> String {
        switch type {
        case .order: return "line.3.horizontal"
        case .alphabetical: return "textformat.abc"
        case .dateModified: return "calendar"
        }
    }
    
    /// Initializes sort orders for categories and items if they are not set.
    private func initializeSortOrders() {
        // Initialize category sort orders if there's multiple categories without a sort order
        let categoriesNeedingOrder = categories.filter { $0.sortOrder == 0 }
        if categoriesNeedingOrder.count > 1 {
            for (index, category) in categoriesNeedingOrder.enumerated() {
                category.sortOrder = index
            }
        }
        
        // Initialize item sort orders if there's multiple items without a sort order
        let itemsNeedingOrder = items.filter { $0.sortOrder == 0 }
        if itemsNeedingOrder.count > 1 {
            for (index, item) in itemsNeedingOrder.enumerated() {
                item.sortOrder = index
            }
        }
    }
    
    /// Returns a greeting based on the current time of day.
    private func greetingTime() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning 🌤️"
        case 12..<17:
            return "Good Afternoon ⛅️"
        default:
            return "Good Evening 🌙"
        }
    }
    
    /// Handles the deletion of items from the inventory.
    /// - Parameter offsets: The offsets of the items to delete.
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    /// Updates the user activity with the current category and sort type.
    /// - Parameter activity: The user activity to update.
    private func updateUserActivity(_ activity: NSUserActivity) {
        activity.addUserInfoEntries(from: [inventoryCategoryKey: selectedCategory])
        activity.title = "View \(selectedCategory) Inventory"
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.keywords = Set([selectedCategory])
        activity.persistentIdentifier = "category-\(selectedCategory)"
    }
}

#Preview {
    @Previewable @State var showItemCreationView: Bool = false
    @Previewable @State var showItemView: Bool = false
    @Previewable @State var selectedItem: Item? = nil
    @Previewable @State var isActive: Bool = true
    InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem, isActive: isActive)
        .modelContainer(for: Item.self)
        .modelContainer(for: Location.self)
        .modelContainer(for: Category.self)
}

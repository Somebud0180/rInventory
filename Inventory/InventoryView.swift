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

enum SortType: String, CaseIterable, Identifiable {
    case order = "Order"
    case alphabetical = "A-Z"
    case dateModified = "Date Modified"
    var id: String { rawValue }
}

// Custom transferable wrapper for Item
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
    @State var emptyItem = Item(name: "Create an item", quantity: 1, location: Location(name: "Press the plus button on the top right", color: .white ), category: nil, imageData: nil, symbol: "plus.circle", symbolColor: .white)
    
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 16)
    ]
    
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
    
    private func updateUserActivity(_ activity: NSUserActivity) {
        activity.addUserInfoEntries(from: [inventoryCategoryKey: selectedCategory])
        activity.title = "View \(selectedCategory) Inventory"
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.keywords = Set([selectedCategory])
        activity.persistentIdentifier = "category-\(selectedCategory)"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                headerSection
                    .padding(.horizontal, 20)
                
                HStack(alignment: .bottom) {
                    categorySelector
                        .padding(.horizontal)
                    Spacer()
                    sortMenu
                        .padding(.horizontal)
                }
                
                Spacer(minLength: 30)
                
                inventoryGrid
                    .padding(.horizontal)
            }
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
    
    private var headerSection: some View {
        Text(greetingTime())
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -10)
    }
    
    private var categorySelector: some View {
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
            CategoryMenuLabel(categoryName: selectedCategory, menuPresented: $categoryMenuPresented)
        }
        .background(colorScheme == .light ? .white.opacity(0.01) : .black.opacity(0.01), in: Capsule())
    }
    
    struct CategoryMenuLabel: View {
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
                            .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()
            }
            .onPreferenceChange(WidthPreferenceKey.self) { newWidth in
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
    
    private var sortMenu: some View {
        Menu {
            ForEach(SortType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedSortType = type
                    }
                } label: {
                    Label(type.rawValue, systemImage: iconName(for: type))
                }
            }
        } label: {
            SortMenuLabel(selectedSortType: selectedSortType, iconName: iconName(for: selectedSortType), menuPresented: $sortMenuPresented)
        }
        .adaptiveGlassButton(tintStrength: 0.0)
    }
    
    struct SortMenuLabel: View {
        let selectedSortType: SortType
        let iconName: String
        @Binding var menuPresented: Bool
        @State private var displayedWidth: CGFloat = 50
        @State private var measuredWidth: CGFloat = 50
        @State private var lastSortType: SortType
        
        init(selectedSortType: SortType, iconName: String, menuPresented: Binding<Bool>) {
            self.selectedSortType = selectedSortType
            self.iconName = iconName
            self._menuPresented = menuPresented
            _lastSortType = State(initialValue: selectedSortType)
        }
        
        var body: some View {
            ZStack {
                // Visible label
                HStack(spacing: 6) {
                    Image(systemName: iconName)
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
                    Image(systemName: iconName)
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
                            .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()
            }
            .onPreferenceChange(WidthPreferenceKey.self) { newWidth in
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
    
    private struct WidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 100
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    private func iconName(for type: SortType) -> String {
        switch type {
        case .order: return "line.3.horizontal"
        case .alphabetical: return "textformat.abc"
        case .dateModified: return "calendar"
        }
    }
    
    private var inventoryGrid: some View {
        LazyVGrid(columns: columns) {
            if items.isEmpty {
                gridCard(item: emptyItem, colorScheme: colorScheme)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    ItemInventoryGridCard(
                        item: item,
                        colorScheme: colorScheme,
                        draggedItem: $draggedItem,
                        onTap: {
                            selectedItem = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                // Add a slight delay to ensure the item is ready
                                showItemView = true
                            }
                        },
                        onDragChanged: { isDragging in
                            draggedItem = isDragging ? item : nil
                        },
                        onDrop: { droppedItemId in
                            handleDrop(droppedItemId: droppedItemId, target: item)
                        }
                    )
                }
            }
        }
    }
    
    private func initializeSortOrders() {
        // Initialize sort orders if they're all 0
        let itemsNeedingOrder = items.filter { $0.sortOrder == 0 }
        if itemsNeedingOrder.count > 1 {
            for (index, item) in itemsNeedingOrder.enumerated() {
                item.sortOrder = index
            }
        }
    }
    
    private func handleDrop(droppedItemId: UUID, target: Item) {
        guard let droppedItem = items.first(where: { $0.id == droppedItemId }),
              droppedItem.id != target.id else {
            draggedItem = nil
            return
        }
        var currentItems = filteredItems
        guard let fromIndex = currentItems.firstIndex(where: { $0.id == droppedItem.id }),
              let toIndex = currentItems.firstIndex(where: { $0.id == target.id }) else {
            draggedItem = nil
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            // Remove & insert dropped item at new index
            let removed = currentItems.remove(at: fromIndex)
            currentItems.insert(removed, at: toIndex)
            
            // Assign new sort orders in array order
            for (newOrder, item) in currentItems.enumerated() {
                item.sortOrder = newOrder
            }
        }
        draggedItem = nil
    }
    
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
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

struct ItemInventoryGridCard: View {
    let item: Item
    let colorScheme: ColorScheme
    @Binding var draggedItem: Item?
    let onTap: () -> Void
    let onDragChanged: (Bool) -> Void
    let onDrop: (UUID) -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.interactiveSpring()) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.interactiveSpring()) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            gridCard(item: item, colorScheme: colorScheme)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
        .scaleEffect(draggedItem?.id == item.id ? 0.93 : (isPressed ? 1.0 : (isHovered ? 0.98 : 0.96)))
        .animation(.interactiveSpring(), value: isPressed)
        .animation(.interactiveSpring(), value: isHovered)
        .draggable(ItemIdentifier(id: item.id)) {
            gridCard(item: item, colorScheme: colorScheme)
                .frame(width: 150, height: 150)
                .opacity(0.8)
        }
        .dropDestination(for: ItemIdentifier.self) { droppedItems, location in
            guard let droppedItem = droppedItems.first else { return false }
            onDrop(droppedItem.id)
            return true
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7, blendDuration: 0.22)) {
                isHovered = hovering
            }
        }
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

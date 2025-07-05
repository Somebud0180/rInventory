//
//  InventoryView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    
    @State private var sortMenuPresented = false
    @State private var sortType: SortType = .order
    @State private var selectedCategory: String = "My Inventory"
    @State private var draggedItem: Item?
    @State var emptyItem = Item(name: "Create an item", quantity: 1, location: Location(name: "Press the plus button on the top right", color: .white ), category: nil, imageData: nil, symbol: "plus.circle", symbolColor: .white)
    
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 16)
    ]
    
    private var filteredItems: [Item] {
        let filtered = selectedCategory == "My Inventory" ? items : items.filter { $0.category?.name == selectedCategory }
        switch sortType {
        case .order:
            return filtered.sorted(by: { $0.sortOrder < $1.sortOrder })
        case .alphabetical:
            return filtered.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .dateModified:
            return filtered.sorted(by: { ($0.modifiedDate) > ($1.modifiedDate) })
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                headerSection
                    .padding(.horizontal, 20)
                
                categorySelector
                
                HStack {
                    Spacer()
                    sortMenu
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                
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
        .navigationViewStyle(.stack)
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
            Button("My Inventory") { selectedCategory = "My Inventory" }
            ForEach(categories, id: \.name) { category in
                Button(category.name) { selectedCategory = category.name }
            }
        } label: {
            HStack {
                Text(selectedCategory)
                    .font(.headline)
                    .foregroundStyle(colorScheme == .light ? .black : .white)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .frame(minWidth: 150)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .animation(.none, value: selectedCategory)
        }
    }
    
    private var sortMenu: some View {
        Menu {
            ForEach(SortType.allCases) { type in
                Button {
                    sortType = type
                } label: {
                    Label(type.rawValue, systemImage: iconName(for: type))
                }
            }
        } label: {
            SortMenuLabel(sortType: sortType, iconName: iconName(for: sortType), menuPresented: $sortMenuPresented)
                .adaptiveGlass(tint: Color(.systemGray5))
        }
    }
    
    struct SortMenuLabel: View {
        let sortType: SortType
        let iconName: String
        @Binding var menuPresented: Bool
        @State private var displayedWidth: CGFloat = 100
        @State private var measuredWidth: CGFloat = 100
        @State private var lastSortType: SortType
        
        init(sortType: SortType, iconName: String, menuPresented: Binding<Bool>) {
            self.sortType = sortType
            self.iconName = iconName
            self._menuPresented = menuPresented
            _lastSortType = State(initialValue: sortType)
        }
        
        var body: some View {
            ZStack {
                // Visible label
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.body)
                    Text(sortType.rawValue)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: displayedWidth)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .foregroundColor(.primary)
                
                // Hidden label for measurement
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.body)
                    Text(sortType.rawValue)
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
                let width = max(newWidth, 100)
                measuredWidth = width
            }
            .onChange(of: sortType) {
                lastSortType = sortType
                // Wait until menu is closed before expanding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !menuPresented {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            displayedWidth = measuredWidth
                        }
                    }
                }
            }
            .onChange(of: menuPresented) {
                if !menuPresented {
                    // When menu closes, animate to new width if needed
                    withAnimation(.easeInOut(duration: 0.35)) {
                        displayedWidth = measuredWidth
                    }
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
        LazyVGrid(columns: columns, spacing: 16) {
            if items.isEmpty {
                gridCard(item: emptyItem, colorScheme: colorScheme)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    ItemGridCard(
                        item: item,
                        colorScheme: colorScheme,
                        draggedItem: $draggedItem,
                        onTap: {
                            selectedItem = item
                            showItemView = true
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

struct ItemGridCard: View {
    let item: Item
    let colorScheme: ColorScheme
    @Binding var draggedItem: Item?
    let onTap: () -> Void
    let onDragChanged: (Bool) -> Void
    let onDrop: (UUID) -> Void
    
    var body: some View {
        Button(action: {
            onTap()
        }) {
            gridCard(item: item, colorScheme: colorScheme)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
        .scaleEffect(draggedItem?.id == item.id ? 0.95 : 1.0)
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
    }
}

#Preview {
    @Previewable @State var showItemCreationView: Bool = false
    @Previewable @State var showItemView: Bool = false
    @Previewable @State var selectedItem: Item? = nil
    InventoryView(showItemCreationView: $showItemCreationView, showItemView: $showItemView, selectedItem: $selectedItem)
        .modelContainer(for: Item.self)
}

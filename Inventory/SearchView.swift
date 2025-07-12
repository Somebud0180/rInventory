//
//  SearchView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view allows users to search for items and filter them by category. It displays a grid of items that match the search criteria and selected category.

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var categories: [Category]
    
    @Binding var showItemView: Bool
    @Binding var selectedItem: Item?
    @State var isActive: Bool
    
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "My Inventory"
    @State private var categoryMenuPresented: Bool = false
    
    private var filteredItems: [Item] {
        let categoryFiltered = selectedCategory == "My Inventory" ?
        items :
        items.filter { $0.category?.name == selectedCategory }
        
        if searchText.isEmpty {
            return categoryFiltered
        } else {
            return categoryFiltered.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.location!.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                categorySelector
                .padding(.vertical)
                
                ScrollView {
                    if filteredItems.isEmpty {
                        Text("No items found")
                            .foregroundColor(.gray)
                            .padding(10)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16, content: {
                            
                            ForEach(filteredItems, id: \.id) { item in
                                ItemSearchGridCard(item: item, colorScheme: colorScheme) {
                                    selectedItem = item
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        // Add a slight delay to ensure the item is ready
                                        showItemView = true
                                    }
                                }
                            }
                        })
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search items and locations")
        }
        // User activity for continuing search state in inventory tab
        .userActivity("ethanj.Inventory.searchingInventory", isActive: isActive) { activity in
            activity.title = "Searching Inventory"
            activity.userInfo = ["tabSelection": 2] // 2 = Search tab
        }
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
    
    private struct WidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 50
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    struct ItemSearchGridCard: View {
        let item: Item
        let colorScheme: ColorScheme
        let onTap: () -> Void
        
        @State private var isPressed = false
        @State private var isHovered = false
        
        var body: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isPressed = false
                    onTap()
                }
            } label: {
                gridCard(item: item, colorScheme: colorScheme)
                    .scaleEffect(isPressed ? 1.0 : (isHovered ? 0.98 : 0.96))
                    .animation(.easeInOut(duration: 0.2), value: isPressed)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var showItemView: Bool = false
    @Previewable @State var selectedItem: Item? = nil
    @Previewable @State var isActive: Bool = true
    // Provide a constant true for isActive to represent the view being active in preview
    SearchView(showItemView: $showItemView, selectedItem: $selectedItem, isActive: isActive)
        .modelContainer(for: Item.self)
        .modelContainer(for: Location.self)
        .modelContainer(for: Category.self)
}

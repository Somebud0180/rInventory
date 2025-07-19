//
//  SearchView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view allows users to search for items and filter them by category. It displays a grid of items that match the search criteria and selected category.

import SwiftUI
import SwiftData

let searchActivityType = "ethanj.Inventory.searchingInventory"
let searchCategoryKey = "category"

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var categories: [Category]
    
    @Binding var showItemView: Bool
    @Binding var selectedItem: Item?
    @State var isActive: Bool
    
    @SceneStorage("SearchView.selectedCategory") private var selectedCategory: String = "All Items"
    @State private var searchText: String = ""
    @State private var categoryMenuPresented: Bool = false
    
    private var filteredItems: [Item] {
        let categoryFiltered = selectedCategory == "All Items" ?
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
                        LazyVGrid(columns: itemColumns, content: {
                            
                            ForEach(filteredItems, id: \.id) { item in
                                ItemCard(
                                    item: item,
                                    colorScheme: colorScheme,
                                    onTap: {
                                        selectedItem = item
                                    }
                                )}
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
        .userActivity(searchActivityType, isActive: isActive) { activity in
            updateUserActivity(activity)
        }
        .onContinueUserActivity(searchActivityType) { activity in
            if let info = activity.userInfo {
                // Handle case of deleted categories by verifying existence before assignment
                if let cat = info[searchCategoryKey] as? String {
                    if categories.contains(where: { $0.name == cat }) {
                        selectedCategory = cat
                    } else {
                        selectedCategory = "All Items"
                    }
                }
            }
        }
    }
    
    private var categorySelector: some View {
        Menu {
            Button("All Items") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedCategory = "All Items"
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
    
    private func updateUserActivity(_ activity: NSUserActivity) {
        activity.addUserInfoEntries(from: [searchCategoryKey: selectedCategory])
        activity.title = "Search \(selectedCategory)"
        activity.userInfo = ["tabSelection": 2]
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.keywords = Set([selectedCategory])
        activity.persistentIdentifier = "category-\(selectedCategory)"
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

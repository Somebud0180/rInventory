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
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "My Inventory"
    
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
        NavigationView {
            VStack(spacing: 0) {
                // Category picker
                Menu {
                    Button("My Inventory") {
                        selectedCategory = "My Inventory"
                    }
                    ForEach(categories, id: \.name) { category in
                        Button(category.name) {
                            selectedCategory = category.name
                        }
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
                .padding(.vertical)
                
                ScrollView {
                    if filteredItems.isEmpty {
                        Text("No items found")
                            .foregroundColor(.gray)
                            .padding(10)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16, content: {
                            
                            ForEach(filteredItems, id: \.id) { item in
                                gridCard(item: item, colorScheme: colorScheme)
                                    .onTapGesture {
                                        selectedItem = item
                                        showItemView = true
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
        }.navigationViewStyle(.stack)
    }
}

#Preview {
    @Previewable @State var showItemView: Bool = false
    @Previewable @State var selectedItem: Item? = nil
    SearchView(showItemView: $showItemView, selectedItem: $selectedItem)
        .modelContainer(for: Item.self)
        .modelContainer(for: Location.self)
        .modelContainer(for: Category.self)
}

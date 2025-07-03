//
//  SearchView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query private var categories: [Category]
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
                item.location.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search items...", text: $searchText)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
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
                        LazyVGrid(columns: columns, content: {
                            
                            ForEach(filteredItems, id: \.id) { item in
                                gridCard(
                                    name: item.name,
                                    location: item.location.name,
                                    locColor: item.location.color,
                                    category: item.category?.name,
                                    background: item.imageData != nil ? .image(item.imageData!) : .symbol(item.symbol ?? "questionmark.circle"),
                                    symbolColor: item.symbolColor,
                                    colorScheme: colorScheme
                                )
                            }
                        })
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    SearchView()
        .modelContainer(for: Item.self)
}

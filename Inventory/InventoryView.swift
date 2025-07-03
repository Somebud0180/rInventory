//
//  InventoryView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//


// Home Tab
import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query private var categories: [Category]
    private var filteredItems: [Item] {
        if selectedCategory == "My Inventory" {
            return items
        } else {
            return items.filter { $0.category?.name == selectedCategory }
        }
    }
    
    @Binding var showItemCreationView: Bool
    @State private var selectedCategory: String = "My Inventory"
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(greetingTime())
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -10)
                
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
                
                Spacer(minLength: 30)
                
                LazyVGrid(columns: columns, content: {
                    if items.isEmpty {
                        gridCard(
                            name: "Create an item",
                            location: "Press the plus button on the top right",
                            locColor: nil,
                            category: nil,
                            background: .symbol("plus.circle"),
                            symbolColor: .white,
                            colorScheme: colorScheme
                        )
                    } else {
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
                    }
                })
            }
            .padding(.horizontal)
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
        }
    }
    
    private func greetingTime() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
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

#Preview {
    @Previewable @State var showItemCreationView: Bool = false
    InventoryView(showItemCreationView: $showItemCreationView)
        .modelContainer(for: Item.self)
}

//
//  SearchView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/14/25.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var locations: [Location]
    @Query private var categories: [Category]
    
    @State var selectedItem: Item?
    @State var showItemView: Bool = false
    
    @State private var selectedCategoryName: String = ""
    @State private var selectedLocationName: String = ""
    @State private var searchText: String = ""
    @State private var categoryFilter: String = ""
    @State private var locationFilter: String = ""
    @State private var categoryMenuPresented: Bool = false
    @State private var locationMenuPresented: Bool = false
    @State private var isCategoriesExpanded: Bool = true
    @State private var isLocationsExpanded: Bool = true
    
    private var filteredItems: [Item] {
        var filtered = items
        
        // Apply category filter if selected
        if !selectedCategoryName.isEmpty {
            filtered = filtered.filter { $0.category?.name == selectedCategoryName }
        }
        
        // Apply location filter if selected
        if !selectedLocationName.isEmpty {
            filtered = filtered.filter { $0.location?.name == selectedLocationName }
        }
        
        // Apply search text
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.name.localizedStandardContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                filterSection
                    .padding(.horizontal)
                
                if filteredItems.isEmpty {
                    Text("No items found")
                        .foregroundColor(.gray)
                        .padding(5)
                } else {
                    LazyVGrid(columns: gridColumns) {
                        if #available(watchOS 26.0, *) {
                            GlassEffectContainer {
                                ForEach(filteredItems, id: \.id) { item in
                                    ItemCard(
                                        item: item,
                                        colorScheme: colorScheme,
                                        showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                                        onTap: {
                                            selectedItem = item
                                            showItemView = true
                                        }
                                    )
                                    .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                                }
                            }
                        } else {
                            ForEach(filteredItems, id: \.id) { item in
                                ItemCard(
                                    item: item,
                                    colorScheme: colorScheme,
                                    showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                                    onTap: {
                                        selectedItem = item
                                        showItemView = true
                                    }
                                )
                                .sensoryFeedback(.impact(flexibility: .soft), trigger: showItemView == true)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search items")
            .fullScreenCover(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                if let selectedItem {
                    ItemView(item: bindingForItem(selectedItem, items))
                        .transition(.blurReplace)
                } else {
                    ProgressView("Loading item...")
                }
            }
        }
    }
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Category filter section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Categories")
                        .font(.headline)
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCategoriesExpanded.toggle()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(isCategoriesExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(minHeight: 24)
                
                // Show horizontal scrolling categories when expanded
                if isCategoriesExpanded {
                    if selectedCategoryName.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if #available(watchOS 26.0, *) {
                                    GlassEffectContainer {
                                        ForEach(categories.sorted(by: { $0.name < $1.name }), id: \.self) { category in
                                            Button(action: {
                                                withAnimation {
                                                    selectedCategoryName = selectedCategoryName == category.name ? "" : category.name
                                                }
                                            }) {
                                                Text(category.name)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                            }
                                            .buttonStyle(.plain)
                                            .adaptiveGlassButton(tintStrength: 0.4)
                                        }
                                    }
                                } else {
                                    ForEach(categories.sorted(by: { $0.name < $1.name }), id: \.self) { category in
                                        Button(action: {
                                            withAnimation {
                                                selectedCategoryName = selectedCategoryName == category.name ? "" : category.name
                                            }
                                        }) {
                                            Text(category.name)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                        }
                                        .buttonStyle(.plain)
                                        .adaptiveGlassButton(tintStrength: 0.4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        HStack {
                            Button(action: {
                                withAnimation {
                                    selectedCategoryName = ""
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(selectedCategoryName)
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .adaptiveGlassButton(tintStrength: 0.6)
                        }
                    }
                }
            }
            
            // Location filter section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Locations")
                        .font(.headline)
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLocationsExpanded.toggle()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(isLocationsExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(minHeight: 24)
                
                // Show horizontal scrolling locations when expanded
                if isLocationsExpanded {
                    if selectedLocationName.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if #available(watchOS 26.0, *) {
                                    GlassEffectContainer {
                                        ForEach(locations.sorted(by: { $0.name < $1.name }), id: \.self) { location in
                                            Button(action: {
                                                withAnimation {
                                                    selectedLocationName = selectedLocationName == location.name ? "" : location.name
                                                }
                                            }) {
                                                Text(location.name)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .adaptiveGlassButton(tintStrength: 0.4, tintColor: location.color)
                                        }
                                    }
                                } else {
                                    ForEach(locations.sorted(by: { $0.name < $1.name }), id: \.self) { location in
                                        Button(action: {
                                            withAnimation {
                                                selectedLocationName = selectedLocationName == location.name ? "" : location.name
                                            }
                                        }) {
                                            Text(location.name)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .adaptiveGlassButton(tintStrength: 0.4, tintColor: location.color)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        HStack {
                            let locationColor = locations.first(where: { $0.name == selectedLocationName })?.color ?? .white
                            Button(action: {
                                withAnimation {
                                    selectedLocationName = ""
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(selectedLocationName)
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .adaptiveGlassButton(tintStrength: 0.6, tintColor: locationColor)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SearchView()
}

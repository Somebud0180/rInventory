//
//  SearchView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/14/25.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @EnvironmentObject var appDefaults: AppDefaults
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedCategoryName: String = ""
    @State private var selectedLocationName: String = ""
    @State private var searchText: String = ""
    
    @Query private var items: [Item]
    @Query(sort: \Location.name) private var locations: [Location]
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State var selectedItem: Item?
    @State var showItemView: Bool = false
    
    @State private var categoryFilter: String = ""
    @State private var locationFilter: String = ""
    @State private var categoryMenuPresented: Bool = false
    @State private var locationMenuPresented: Bool = false
    @State private var isCategoriesExpanded: Bool = true
    @State private var isLocationsExpanded: Bool = true
    
    // State for image prefetching
    @State private var visibleItemIDs = Set<UUID>()
    @State private var prefetchingEnabled = true
    private let prefetchBatchSize = 6 // Smaller batch size for watch
    
    private var filteredItems: [Item] {
        var filtered = items
        if !selectedCategoryName.isEmpty {
            filtered = filtered.filter { $0.category?.name == selectedCategoryName }
        }
        if !selectedLocationName.isEmpty {
            filtered = filtered.filter { $0.location?.name == selectedLocationName }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.name.localizedStandardContains(searchText)
            }
        }
        return filtered
    }
    
    var body: some View {
        let upcomingItems = calculateUpcomingItems(filteredItems, visibleItemIDs: visibleItemIDs, prefetchBatchSize: prefetchBatchSize)
        
        NavigationStack {
            ScrollView {
                filterSection
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                
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
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search items")
            .fullScreenCover(isPresented: $showItemView, onDismiss: { selectedItem = nil }) {
                ItemView(item: $selectedItem)
            }
            .onAppear {
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
            .onDisappear {
                // Cancel all prefetching when view disappears
                if prefetchingEnabled {
                    ItemImagePrefetcher.cancelAllPrefetching()
                    visibleItemIDs.removeAll()
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
                                ForEach(categories, id: \.self) { category in
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
                                }.glassContain()
                            }.padding(.vertical, 4)
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
                                ForEach(locations, id: \.self) { location in
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
                                }.glassContain()
                            }.padding(.vertical, 4)
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
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

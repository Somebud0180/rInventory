//
//  SearchView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view allows users to search for items and filter them by category. It displays a grid of items that match the search criteria and selected category.

import SwiftUI
import SwiftData

let searchActivityType = "com.lagera.Inventory.searchingInventory"
let searchCategoryKey = "category"
let searchLocationKey = "location"

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    @Query private var items: [Item]
    @Query private var categories: [Category]
    @Query private var locations: [Location]
    
    @StateObject var syncEngine: CloudKitSyncEngine
    @State var isActive: Bool
    
    @SceneStorage("SearchView.selectedCategory") private var selectedCategoryName: String = ""
    @SceneStorage("SearchView.selectedLocation") private var selectedLocationName: String = ""
    @State private var searchText: String = ""
    @State private var categoryFilter: String = ""
    @State private var locationFilter: String = ""
    @State private var showItemView: Bool = false
    @State private var selectedItem: Item? = nil
    @State private var showCategoryMenu: Bool = false
    @State private var showLocationMenu: Bool = false
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
            VStack(spacing: 8) {
                filterSection
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                ScrollView {
                    if filteredItems.isEmpty {
                        Text("No items found")
                            .foregroundColor(.gray)
                            .padding(10)
                    } else {
                        LazyVGrid(columns: itemColumns) {
                            ForEach(filteredItems, id: \.id) { item in
                                ItemCard(
                                    item: item,
                                    colorScheme: colorScheme,
                                    showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems,
                                    onTap: {
                                        selectedItem = item
                                    }
                                )}
                        }.padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search items")
            .sheet(isPresented: $showItemView, onDismiss: {
                selectedItem = nil
            }) {
                if let selectedItem = selectedItem {
                    ItemView(syncEngine: syncEngine, item: bindingForItem(selectedItem, items: items))
                }
            }
        }
        // User activity for continuing search state in inventory tab
        .userActivity(searchActivityType, isActive: isActive) { activity in
            updateUserActivity(activity)
        }
        .onContinueUserActivity(searchActivityType) { activity in
            if let info = activity.userInfo {
                // Handle case of deleted categories by verifying existence before assignment
                if let cat = info[searchCategoryKey] as? String {
                    if !cat.isEmpty && categories.contains(where: { $0.name == cat }) {
                        selectedCategoryName = cat
                    } else {
                        selectedCategoryName = ""
                    }
                }
                if let loc = info[searchLocationKey] as? String {
                    if !loc.isEmpty && locations.contains(where: { $0.name == loc }) {
                        selectedLocationName = loc
                    } else {
                        selectedLocationName = ""
                    }
                }
            }
        }
    }
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category filter section
            VStack(alignment: .leading, spacing: 8) {
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
                    
                    if !selectedCategoryName.isEmpty {
                        Button(action: {
                            selectedCategoryName = ""
                        }) {
                            HStack(spacing: 4) {
                                Text(selectedCategoryName)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .adaptiveGlassButton(tintStrength: 0.6)
                    }
                }
                .frame(minHeight: 24)
                
                // Show horizontal scrolling categories when expanded
                if isCategoriesExpanded {
                    categoriesScroll
                }
            }
            
            // Location filter section
            VStack(alignment: .leading, spacing: 8) {
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
                    
                    if !selectedLocationName.isEmpty {
                        let locationColor = locations.first(where: { $0.name == selectedLocationName })?.color ?? .white
                        Button(action: {
                            selectedLocationName = ""
                        }) {
                            HStack(spacing: 4) {
                                Text(selectedLocationName)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .adaptiveGlassButton(tintStrength: 0.6, tintColor: locationColor)
                    }
                }
                .frame(minHeight: 24)
                
                // Show horizontal scrolling locations when expanded
                if isLocationsExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            locationScroll
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollClipDisabled()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    private var categoriesScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories.sorted(by: { $0.name < $1.name }), id: \.self) { category in
                    Button(action: {
                        withAnimation {
                            selectedCategoryName = selectedCategoryName == category.name ? "" : category.name
                        }
                    }) {
                        Text(category.name)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlassButton(tintStrength: selectedCategoryName == category.name ? 0.6 : 0.4)
                }
            }
            .glassContain()
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var locationScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(locations.sorted(by: { $0.name < $1.name }), id: \.self) { location in
                    Button(action: {
                        withAnimation {
                            selectedLocationName = selectedLocationName == location.name ? "" : location.name
                        }
                    }) {
                        Text(location.name)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlassButton(tintStrength: selectedLocationName == location.name ? 0.6 : 0.4, tintColor: location.color)
                }
            }
            .glassContain()
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func updateUserActivity(_ activity: NSUserActivity) {
        activity.addUserInfoEntries(from: [searchCategoryKey: selectedCategoryName, searchLocationKey: selectedLocationName])
        if selectedCategoryName.isEmpty && selectedLocationName.isEmpty {
            activity.title = "Search rInventory"
        } else {
            let titleString = "\(selectedLocationName) \(selectedCategoryName)".trimmingCharacters(in: .whitespaces)
            activity.title = "Search rInventory: \(titleString)"
        }
        activity.userInfo = ["tabSelection": 2]
        activity.isEligibleForHandoff = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
    }
}

#Preview {
    // Provide a constant true for isActive to represent the view being active in preview
    @Previewable @State var isActive: Bool = true
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    SearchView(syncEngine: syncEngine, isActive: isActive)
        .modelContainer(for: Item.self)
        .modelContainer(for: Location.self)
        .modelContainer(for: Category.self)
}

//
//  FilteredSuggestions.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/12/25.
//

import Foundation
import SwiftUI
import SwiftData

private func filteredSuggestions<T>(_ items: [T], keyPath: KeyPath<T, String>, filter: String) -> [String] {
    let names = Set(items.map { $0[keyPath: keyPath] })
    let sorted = names.sorted()
    if filter.isEmpty {
        return sorted
    } else {
        return sorted.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}

// Example usage in a main view:
// filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $searchText)
// filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $searchText)
func filteredSuggestionsPicker<T>(items: [T], keyPath: KeyPath<T, String>, filter: Binding<String>) -> some View {
    let suggestions = filteredSuggestions(items, keyPath: keyPath, filter: filter.wrappedValue)
    if suggestions.isEmpty {
        return AnyView(EmptyView())
    }
    
    // Helper: If items are Location, map the name to color
    let getColor: (String) -> Color = {
        if let locations = items as? [Location] {
            return { name in
                locations.first(where: { $0.name == name })?.color ?? .white
            }
        } else {
            return { _ in .white }
        }
    }()
    
    return AnyView(
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        filter.wrappedValue = suggestion
                    }
                    .padding(4)
                    .padding(.horizontal, 4)
                    .foregroundStyle(getColor(suggestion))
                    .adaptiveGlassBackground(tintStrength: 0.5)
                }
            }
        }
            .clipShape(Capsule())
    )
}

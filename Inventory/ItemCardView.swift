//
//  ItemCardView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view displays the item card, showing its symbol or image, name, quantity, location, and category.

import SwiftUI
import SwiftData

enum ItemCardBackground {
    case symbol(String)
    case image(Data)
}

/// Creates a item card view for displaying item information in a layout.
/// - Parameters:
///   - name: The name of the item.
///   - quantity: The quantity of the item.
///   - location: The location of the item.
///   - category: The category of the item.
///   - background: The background type for the card, either a symbol or an image.
///   - symbolColor: The color of the symbol, if applicable.
///   - colorScheme: The current color scheme of the app.
///   - largeFont: Optional boolean to determine if a larger font should be used for the item name.
///   - hideQuantity: Optional boolean to hide the quantity label.
///   - Returns: A view representing the item card with the specified properties.
///   This function creates a visually appealing card that can be used in layouts, with adaptive glass background effects and responsive design.
func itemCard(name: String, quantity: Int, location: Location, category: Category, background: ItemCardBackground, symbolColor: Color? = nil, colorScheme: ColorScheme, largeFont: Bool? = false, hideQuantity: Bool = false) -> some View {
    let largeFont = largeFont ?? false
    return ZStack {
        RoundedRectangle(cornerRadius: 25.0)
            .aspectRatio(contentMode: .fill)
            .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
        
        GeometryReader { geometry in
            switch background {
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(symbolColor ?? .accentColor)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .padding(25)
                
            case .image(let data):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    EmptyView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25.0))
        
        LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
            .mask(RoundedRectangle(cornerRadius: 25.0)
                .aspectRatio(contentMode: .fill))
        
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !category.name.isEmpty {
                    Text(category.name)
                        .font(largeFont ? .system(.callout, design: .rounded) : .system(.footnote, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(8)
                        .adaptiveGlassBackground(tintStrength: 0.5)
                }
                if hideQuantity {
                    Spacer(minLength: 32)
                } else {
                    if quantity > 0 {
                        Spacer()
                        Text("\(quantity)")
                            .font(largeFont ? .system(.callout, design: .rounded) : .system(.footnote, design: .rounded))
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(8)
                            .padding(.horizontal, 4)
                            .adaptiveGlassBackground(tintStrength: 0.5)
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(largeFont ? .system(.title, design: .rounded) : .system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.95))
                if !location.name.isEmpty {
                    Text(location.name)
                        .font(largeFont ? .system(.callout, design: .rounded) : .system(.footnote, design: .rounded))
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(location.color)
                }
            }
            .padding(4)
            .padding(.horizontal, 4)
            .adaptiveGlassBackground(tintStrength: 0.5, shape: RoundedRectangle(cornerRadius: 15.0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
    .aspectRatio(1.0, contentMode: .fit)
}

/// Creates a item card view for displaying the item information in a layout.
/// - Parameters:
///  - item: The item to display.
///  - colorScheme: The current color scheme of the app.
///  - hideQuantity: Optional boolean to hide the quantity label.
///  - Returns: A view representing the item card with the item's properties.
///  This function creates a visually appealing card that can be used in layouts, with adaptive glass background effects and responsive design.
func itemCard(item: Item, colorScheme: ColorScheme, hideQuantity: Bool = false) -> some View {
    let location = item.location ?? Location(name: "Unknown", color: .white)
    let category = item.category ?? Category(name: "")
    
    let background: ItemCardBackground
    if let imageData = item.imageData, !imageData.isEmpty {
        background = .image(imageData)
    } else if let symbol = item.symbol {
        background = .symbol(symbol)
    } else {
        background = .symbol("questionmark")
    }
    
    return itemCard(
        name: item.name,
        quantity: item.quantity,
        location: location,
        category: category,
        background: background,
        symbolColor: item.symbolColor,
        colorScheme: colorScheme,
        hideQuantity: hideQuantity
    )
}

func handleDrop(_ items: [Item], filteredItems: [Item],draggedItem: Binding<Item?>, droppedItemId: UUID, target: Item) {
    guard let droppedItem = items.first(where: { $0.id == droppedItemId }),
          droppedItem.id != target.id else {
        draggedItem.wrappedValue = nil
        return
    }
    var currentItems = filteredItems
    guard let fromIndex = currentItems.firstIndex(where: { $0.id == droppedItem.id }),
          let toIndex = currentItems.firstIndex(where: { $0.id == target.id }) else {
        draggedItem.wrappedValue = nil
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
    draggedItem.wrappedValue = nil
}

struct ItemCard: View {
    let item: Item
    let colorScheme: ColorScheme
    var onTap: () -> Void = {}
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            withAnimation(.interactiveSpring()) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.interactiveSpring()) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            itemCard(item: item, colorScheme: colorScheme)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 1.0 : (isHovered ? 0.98 : 0.96))
        .animation(.interactiveSpring(), value: isPressed)
        .animation(.interactiveSpring(), value: isHovered)
        .draggable(ItemIdentifier(id: item.id)) {
            itemCard(item: item, colorScheme: colorScheme)
                .frame(width: 150, height: 150)
                .opacity(0.8)
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7, blendDuration: 0.22)) {
                isHovered = hovering
            }
        }
    }
}

struct DraggableItemCard: View {
    let item: Item
    let colorScheme: ColorScheme
    @Binding var draggedItem: Item?
    var onTap: () -> Void = {}
    var onDragChanged: (Bool) -> Void
    var onDrop: (UUID) -> Void
    
    var isEditing: Bool
    var isSelected: Bool = false
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            withAnimation(.interactiveSpring()) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.interactiveSpring()) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            itemCard(item: item, colorScheme: colorScheme, hideQuantity: isEditing)
                .overlay(alignment: .topTrailing) {
                    if isEditing {
                        checkmarkIcon
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
        .scaleEffect(draggedItem?.id == item.id ? 0.93 : (isPressed ? 1.0 : (isHovered ? 0.98 : 0.96)))
        .animation(.interactiveSpring(), value: isPressed)
        .animation(.interactiveSpring(), value: isHovered)
        .draggable(ItemIdentifier(id: item.id)) {
            itemCard(item: item, colorScheme: colorScheme, hideQuantity: isEditing)
                .frame(width: 150, height: 150)
                .opacity(0.8)
                .overlay(alignment: .topTrailing) {
                    if isEditing {
                        checkmarkIcon
                    }
                }
        }
        .dropDestination(for: ItemIdentifier.self) { droppedItems, location in
            guard let droppedItem = droppedItems.first else { return false }
            onDrop(droppedItem.id)
            return true
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7, blendDuration: 0.22)) {
                isHovered = hovering
            }
        }
    }
    
    private var checkmarkIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .foregroundColor(isSelected ? Color.blue : Color.secondary)
            .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 0)
            .padding(12)
    }
}


#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}


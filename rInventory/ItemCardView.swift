//
//  ItemCardView.swift
//  rInventory
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

// MARK: - Constants
struct ItemCardConstants {
    static let backgroundGradient = LinearGradient(
        colors: [.accentDark, .gray],
        startPoint: .top,
        endPoint: .bottom
    )
    static let overlayGradient = LinearGradient(
        colors: [.clear, .black.opacity(0.75)],
        startPoint: .center,
        endPoint: .bottom
    )
    static let cornerRadius: CGFloat = 25.0
    static let aspectRatio: CGFloat = 1.0
}

// MARK: - Font Configuration
private struct FontConfig {
    let titleFont: Font
    let bodyFont: Font
    let captionFont: Font
    
    init(isLarge: Bool) {
        titleFont = .system(isLarge ? .title : .title3, design: .rounded)
        bodyFont = .system(isLarge ? .callout : .footnote, design: .rounded)
        captionFont = .system(isLarge ? .callout : .footnote, design: .rounded)
    }
}

// MARK: - Animation Modifier
private struct ItemCardAnimationModifier: ViewModifier {
    let isPressed: Bool
    let isHovered: Bool
    let isDragged: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isDragged ? 0.5 : 1.0)
            .scaleEffect(scale)
            .animation(.interactiveSpring(), value: isPressed)
            .animation(.interactiveSpring(), value: isHovered)
    }
    
    private var scale: Double {
        if isDragged { return 0.93 }
        if isPressed { return 1.0 }
        if isHovered { return 0.98 }
        return 0.96
    }
}

// MARK: - Shared Button Behavior
struct ItemCardButton<Content: View>: View {
    let content: Content
    let onTap: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false
    
    init(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) {
        self.content = content()
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: handleTap) {
            content
        }
        .buttonStyle(PlainButtonStyle())
        .modifier(ItemCardAnimationModifier(
            isPressed: isPressed,
            isHovered: isHovered,
            isDragged: false
        ))
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7, blendDuration: 0.22)) {
                isHovered = hovering
            }
        }
    }
    
    private func handleTap() {
        withAnimation(.spring()) {
            isPressed = true
        }
        withAnimation(.spring().delay(0.1)) {
            isPressed = false
        }
        onTap()
    }
}

// MARK: - Core Item Card Function
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
///   - showCounterForSingleItems: Optional boolean to show counter for single items.
///   - Returns: A view representing the item card with the specified properties.
///   This function creates a visually appealing card that can be used in layouts, with adaptive glass background effects and responsive design.
func itemCard(name: String, quantity: Int, location: Location, category: Category, background: ItemCardBackground, symbolColor: Color? = nil, colorScheme: ColorScheme, largeFont: Bool? = false, hideQuantity: Bool = false, simplified: Bool = false, showCounterForSingleItems: Bool = true) -> some View {
    let fontConfig = FontConfig(isLarge: largeFont ?? false)
    
    var content: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)
                .aspectRatio(contentMode: .fill)
                .foregroundStyle(ItemCardConstants.backgroundGradient)
            
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
                    AsyncItemImage(imageData: data)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius))
            
            ItemCardConstants.overlayGradient
                .mask(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)
                    .aspectRatio(contentMode: .fill))
            
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if !category.name.isEmpty {
                        Text(category.name)
                            .font(fontConfig.bodyFont)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(8)
                            .adaptiveGlassBackground(tintStrength: 0.5, simplified: simplified)
                    }
                    if hideQuantity {
                        Spacer(minLength: 32)
                    } else {
                        if quantity > 1 || (showCounterForSingleItems && quantity == 1) {
                            Spacer()
                            Text("\(quantity)")
                                .font(fontConfig.bodyFont)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(8)
                                .padding(.horizontal, 4)
                                .adaptiveGlassBackground(tintStrength: 0.5, simplified: simplified, shape: quantity < 10 ? AnyShape(Circle()) : AnyShape(Capsule()))
                        }
                    }
                }
                Spacer()
                if !name.isEmpty || !location.name.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if !name.isEmpty {
                            Text(name)
                                .font(fontConfig.titleFont)
                                .fontWeight(.bold)
                                .lineLimit(1)
                        }
                        if !location.name.isEmpty {
                            Text(location.name)
                                .font(fontConfig.captionFont)
                                .fontWeight(.medium)
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(
                        (!isColorWhite(location.color) || (usesLiquidGlass && colorScheme == .dark))
                        ? .white.opacity(0.95) : .black.opacity(0.95))
                    .padding(4)
                    .padding(.horizontal, 4)
                    .adaptiveGlassBackground(tintStrength: 0.75, tintColor: location.color, simplified: simplified, shape: RoundedRectangle(cornerRadius: 15.0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .aspectRatio(ItemCardConstants.aspectRatio, contentMode: .fit)
    }
    
    if #available(iOS 26, *) {
        return GlassEffectContainer {
            content
        }
    } else {
        return content
    }
}

/// Creates a item card view for displaying the item information in a layout.
/// - Parameters:
///  - item: The item to display.
///  - colorScheme: The current color scheme of the app.
///  - hideQuantity: Optional boolean to hide the quantity label.
///  - showCounterForSingleItems: Optional boolean to show counter for single items.
///  - Returns: A view representing the item card with the item's properties.
///  This function creates a visually appealing card that can be used in layouts, with adaptive glass background effects and responsive design.
func itemCard(item: Item, colorScheme: ColorScheme, hideQuantity: Bool = false, simplified: Bool = false, showCounterForSingleItems: Bool = true) -> some View {
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
        hideQuantity: hideQuantity,
        simplified: simplified,
        showCounterForSingleItems: showCounterForSingleItems
    )
}

// MARK: - Drop Handling
func handleDrop(_ items: [Item], filteredItems: [Item], draggedItem: Binding<Item?>, droppedItemId: UUID, target: Item) {
    defer { draggedItem.wrappedValue = nil }
    
    guard let droppedItem = items.first(where: { $0.id == droppedItemId }),
          droppedItem.id != target.id,
          let fromIndex = filteredItems.firstIndex(where: { $0.id == droppedItem.id }),
          let toIndex = filteredItems.firstIndex(where: { $0.id == target.id }) else {
        return
    }
    
    var currentItems = filteredItems
    withAnimation(.easeInOut(duration: 0.3)) {
        currentItems.move(fromOffsets: IndexSet([fromIndex]), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        
        for (newOrder, item) in currentItems.enumerated() {
            item.sortOrder = newOrder
        }
    }
}

// MARK: - Item Card Views
struct ItemCard: View {
    let item: Item
    let colorScheme: ColorScheme
    var showCounterForSingleItems: Bool = true
    var onTap: () -> Void = {}
    
    var body: some View {
        ItemCardButton {
            itemCard(item: item, colorScheme: colorScheme, showCounterForSingleItems: showCounterForSingleItems)
        } onTap: {
            onTap()
        }
    }
}

struct DraggableItemCard: View {
    let item: Item
    let colorScheme: ColorScheme
    var showCounterForSingleItems: Bool = true
    @Binding var draggedItem: Item?
    var onTap: () -> Void = {}
    var onDragChanged: (Bool) -> Void
    var onDrop: (UUID) -> Void
    
    var isEditing: Bool
    var isSelected: Bool = false
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: handleTap) {
            itemCard(item: item, colorScheme: colorScheme, hideQuantity: isEditing, showCounterForSingleItems: showCounterForSingleItems)
                .overlay(alignment: .topTrailing) {
                    if isEditing {
                        checkmarkIcon
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .modifier(ItemCardAnimationModifier(
            isPressed: isPressed,
            isHovered: isHovered,
            isDragged: draggedItem?.id == item.id
        ))
        .draggable(ItemIdentifier(id: item.id)) {
            itemCard(item: item, colorScheme: colorScheme, hideQuantity: isEditing, simplified: true, showCounterForSingleItems: showCounterForSingleItems)
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
    
    private func handleTap() {
        withAnimation(.spring()) {
            isPressed = true
        }
        withAnimation(.spring().delay(0.1)) {
            isPressed = false
        }
        onTap()
    }
    
    private var checkmarkIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .foregroundColor(isSelected ? Color.blue : Color.white.opacity(0.8))
            .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 0)
            .padding(12)
    }
}

extension Color {
    /// Returns the relative luminance of this color, from 0 (black) to 1 (white).
    func luminance() -> Double {
        // Convert the color to UIColor/NSColor and extract components
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
#else
        let nsColor = NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
#endif
        
        // Calculate luminance (perceptual brightness)
        func channel(_ c: CGFloat) -> Double {
            let c = Double(c)
            return (c <= 0.03928) ? (c/12.92) : pow((c+0.055)/1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}


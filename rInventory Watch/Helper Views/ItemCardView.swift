//
//  ItemCardView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view displays the item card, showing its symbol or image, name, quantity, location, and category.

import SwiftUI
import SwiftData

// MARK: - Constants
struct ItemCardConstants {
    static let cornerRadius: CGFloat = 20.0
    static let aspectRatio: CGFloat = 1.0
    static let backgroundGradient = LinearGradient(
        colors: [Color.accentDark.opacity(0.9), Color.black.opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Font Configuration
struct FontConfig {
    static let titleFont: Font = .system(.title3, design: .rounded)
    static let bodyFont: Font = .system(.footnote, design: .rounded)
    static let captionFont: Font = .system(.footnote, design: .rounded)
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
///   - hideQuantity: Optional boolean to hide the quantity label.
///   - showCounterForSingleItems: Optional boolean to show counter for single items.
///   - Returns: A view representing the item card with the specified properties.
///   This function creates a visually appealing card that can be used in layouts, with adaptive glass background effects and responsive design.
func itemCard(name: String, quantity: Int, location: Location, category: Category, background: ItemCardBackground, symbolColor: Color? = nil, colorScheme: ColorScheme, hideQuantity: Bool = false, simplified: Bool = false, showCounterForSingleItems: Bool = true) -> some View {
    Group {
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
                        .id(data)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            
            location.color
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.25),
                            .init(color: .clear, location: 0.45)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .blur(radius: 12)
                )
            
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if !category.name.isEmpty {
                        Text(category.name)
                            .font(FontConfig.bodyFont)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(4)
                            .adaptiveGlassBackground(tintStrength: 0.5, simplified: simplified)
                    }
                    if hideQuantity {
                        Spacer(minLength: 16)
                    } else {
                        if quantity > 1 || (showCounterForSingleItems && quantity == 1) {
                            Spacer()
                            Text("\(quantity)")
                                .font(FontConfig.bodyFont)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(4)
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
                                .font(FontConfig.titleFont)
                                .fontWeight(.bold)
                                .lineLimit(1)
                        }
                        if !location.name.isEmpty {
                            Text(location.name)
                                .font(FontConfig.captionFont)
                                .fontWeight(.medium)
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(
                        (!location.color.isColorWhite() || (usesLiquidGlass && colorScheme == .dark))
                        ? .white.opacity(0.95) : .black.opacity(0.95))
                    .padding(4)
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius))
        .aspectRatio(ItemCardConstants.aspectRatio, contentMode: .fit)
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

// MARK: - Item Card Views
struct ItemCard: View {
    let item: Item
    let colorScheme: ColorScheme
    var showCounterForSingleItems: Bool = true
    var onTap: () -> Void = {}
    
    var body: some View {
        Button(action: onTap) {
            itemCard(item: item, colorScheme: colorScheme, simplified: true, showCounterForSingleItems: showCounterForSingleItems)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    @Previewable @State var isActive: Bool = true
    
    InventoryView(isActive: isActive)
        .modelContainer(for: [Item.self, Location.self, Category.self])
}

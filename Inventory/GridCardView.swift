//
//  GridCardView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view displays the grid card for an item, showing its symbol or image, name, quantity, location, and category.

import SwiftUI
import SwiftData

enum GridCardBackground {
    case symbol(String)
    case image(Data)
}

func gridCard(name: String, quantity: Int, location: Location, category: Category, background: GridCardBackground, symbolColor: Color? = nil, colorScheme: ColorScheme, largeFont: Bool? = false) -> some View {
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
                        .font(.system(.footnote, design: .rounded))
                        .bold()
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(8)
                        .adaptiveGlassBackground(tintStrength: 0.5)
                }
                Spacer()
                if quantity > 0 {
                    Text("\(quantity)")
                        .font(.system(.footnote, design: .rounded))
                        .bold()
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(8)
                        .padding(.horizontal, 4)
                        .adaptiveGlassBackground(tintStrength: 0.5)
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

func gridCard(item: Item, colorScheme: ColorScheme) -> some View {
    let location = item.location ?? Location(name: "Unknown", color: .white)
    let category = item.category ?? Category(name: "")
    
    let background: GridCardBackground
    if let imageData = item.imageData, !imageData.isEmpty {
        background = .image(imageData)
    } else if let symbol = item.symbol {
        background = .symbol(symbol)
    } else {
        background = .symbol("questionmark")
    }
    
    return gridCard(
        name: item.name,
        quantity: item.quantity,
        location: location,
        category: category,
        background: background,
        symbolColor: item.symbolColor,
        colorScheme: colorScheme
    )
}

#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}

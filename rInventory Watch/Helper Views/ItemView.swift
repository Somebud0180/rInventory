//
//  ItemView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/12/25.
//

import SwiftUI
import SwiftData

/// View for displaying either an image or a symbol background with a mask.
struct ItemBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    let background: ItemCardBackground
    let symbolColor: Color?
    let gradientMask: LinearGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: 0.1),
            .init(color: .white, location: 0.2),
            .init(color: .white, location: 0.8),
            .init(color: .clear, location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
        
    
    var body: some View {
        switch background {
        case .image(let data):
            AsyncItemImage(imageData: data)
                .id(data)
                .if(!AsyncItemImage.hasAlphaChannel(in: data)) { $0.mask(gradientMask.blur(radius: 12)) }
        case .symbol(let symbol):
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(symbolColor ?? .white)
                .padding(12)
        }
    }
}

struct ItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Binding var item: Item?
    
    @State private var isFinishedLoading: Bool = false
    
    // Item display variables - Original values
    @State private var name: String = ""
    @State private var quantity: Int = 0
    @State private var location: Location = Location(name: "Unknown", color: .white)
    @State private var category: Category = Category(name: "")
    @State private var background: ItemCardBackground = .symbol("questionmark")
    @State private var symbolColor: Color? = nil
    
    var body: some View {
        NavigationStack {
            if !isFinishedLoading {
                ProgressView("Loading Item...")
                    .onAppear {
                        initializeDisplayVariables()
                    }
            } else {
                ZStack {
                    GeometryReader { geometry in
                        content(geometry)
                            .glassContain()
                    }
                }
                .ignoresSafeArea()
                .background(backgroundGradient)
            }
        }
        ._statusBarHidden(true)
        
    }
    
    //MARK: - Computed Properties
    private var backgroundGradient: AnyView {
        return AnyView(
            ZStack {
                Rectangle()
                    .foregroundStyle(backgroundLinearGradient)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if case let .image(data) = background {
                    AsyncItemImage(imageData: data)
                        .scaledToFill()
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 44)
                }
            }
        )
    }
    
    private var backgroundLinearGradient: LinearGradient {
        let primaryColor = (colorScheme == .dark || (symbolColor ?? .white).isColorWhite(sensitivity: 0.3)) ? Color.accentDark.opacity(0.9) : Color.accentLight.opacity(0.9)
        let secondaryColor = (colorScheme == .dark || (symbolColor ?? .white).isColorWhite(sensitivity: 0.3)) ? Color.black.opacity(0.9) : Color.gray.opacity(0.9)
        return LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private func content(_ geometry: GeometryProxy) -> some View {
        ZStack {
            ItemBackgroundView(
                background: background,
                symbolColor: symbolColor
            )
            
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.25),
                            .init(color: .clear, location: 0.5)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            
            VStack {
                ZStack {
                    categorySection(geometry)
                    
                    HStack(alignment: .center) {
                        Spacer()
                        quantitySection
                    }
                }.frame(height: 44, alignment: .center)
                
                Spacer()
            }
            .padding(12)
            
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                
                nameSection
                locationSection
                // quantityStepperSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
    
    private func categorySection(_ geometry: GeometryProxy) -> some View {
        Group {
            if !category.name.isEmpty {
                Text(category.name)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(4)
                    .adaptiveGlassBackground(tintStrength: 0.5)
            } else {
                Text("")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(6)
                    .hidden()
            }
        }
        .frame(maxWidth: geometry.size.width * 0.5)
    }
    
    private var quantitySection: some View {
        Group {
            if quantity > 0 {
                Text(String(quantity))
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .lineLimit(1)
                    .padding(8)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 32)
                    .adaptiveGlassBackground(tintStrength: 0.5, shape: quantity < 10 ? AnyShape(Circle()) : AnyShape(Capsule()))
            }
        }
        .minimumScaleFactor(0.75)
        .foregroundStyle(colorScheme == .dark ? .white : .black)
    }
    
    private var nameSection: some View {
        Group {
            Text(name)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.75)
    }
    
    private var locationSection: some View {
        Group {
            Text(location.name)
                .foregroundStyle(
                    (!location.color.isColorWhite() || (usesLiquidGlass && colorScheme == .dark))
                    ? .white : .black)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .adaptiveGlassBackground(tintStrength: 0.5, tintColor: location.color)
        }
    }
    
    //MARK: - Functions
    private func initializeDisplayVariables() {
        if let item = item {
            name = item.name
            quantity = item.quantity
            location = item.location ?? Location(name: "The Void", color: .gray)
            category = item.category ?? Category(name: "")
            
            if let imageData = item.imageData, !imageData.isEmpty {
                background = .image(imageData)
            } else if let symbol = item.symbol {
                background = .symbol(symbol)
            } else {
                background = .symbol("questionmark")
            }
            
            symbolColor = item.symbolColor
            isFinishedLoading = true
        }
    }
}

#Preview {
    @Previewable @State var item: Item? = Item(
        name: "Sample Item",
        quantity: 1,
        location: Location(name: "Sample Location", color: .blue),
        category: Category(name: "Sample Category"),
        imageData: nil,
        symbol: "star.fill",
        symbolColor: .yellow
    )
    
    ItemView(item: $item)
}

//
//  GridCardView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//

import SwiftUI

enum GridCardBackground {
    case symbol(String)
    case image(Data)
}

func gridCard(name: String, location: String, locColor: Color?, category: String? = nil, background: GridCardBackground, symbolColor: Color? = nil, colorScheme: ColorScheme) -> some View {
    return ZStack {
        RoundedRectangle(cornerRadius: 25.0)
            .aspectRatio(contentMode: /*@START_MENU_TOKEN@*/.fill/*@END_MENU_TOKEN@*/)
            .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
        
        GeometryReader { geometry in
            switch background {
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(symbolColor ?? .accentColor)
                    .padding(25)
                
            case .image(let data):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 25.0))
                } else {
                    EmptyView()
                }
            }
        }
        
        LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
            .mask(RoundedRectangle(cornerRadius: 25.0)
                .aspectRatio(contentMode: /*@START_MENU_TOKEN@*/.fill/*@END_MENU_TOKEN@*/))
        VStack {
            if category != nil {
                Text(category ?? "")
                    .font(.system(.footnote, design: .rounded))
                    .bold()
                    .foregroundStyle(.ultraThickMaterial)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 50)
            Text(name)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.95))
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 3,
                    x: 0,
                    y: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .dynamicTypeSize(.xLarge ... .accessibility5)
            Text(location)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(locColor ?? .white)
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 3,
                    x: 0,
                    y: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .dynamicTypeSize(.xLarge ... .accessibility5)
        }.padding()
    }.aspectRatio(1.0, contentMode: .fit)
}

#Preview {
    ItemCreationView()
}

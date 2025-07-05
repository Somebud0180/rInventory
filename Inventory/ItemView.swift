//
//  ItemView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI
import SwiftData

struct ItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var categories: [Category]
    @Query private var locations: [Location]
    
    enum GridCardBackground {
        case symbol(String)
        case image(Data)
    }
    
    @Binding var item: Item
    
    @State var isEditing: Bool = false
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropper: Bool = false
    
    @State private var imageToCrop: UIImage? = nil
    
    @State private var newName: String = ""
    @State private var newLocation: Location = Location(name: "", color: .white)
    @State private var newCategory: Category = Category(name: "")
    @State private var newBackground: GridCardBackground = .symbol("questionmark")
    @State private var newSymbolColor: Color? = nil
    
    // Helper to get suggestions
    private var categorySuggestions: [String] {
        Array(Set(categories.map { $0.name })).sorted()
    }
    
    private var filteredCategorySuggestions: [String] {
        newCategory.name.isEmpty ? categorySuggestions : categorySuggestions.filter { $0.localizedCaseInsensitiveContains(newCategory.name) }
    }
    
    private var locationSuggestions: [String] {
        Array(Set(locations.map { $0.name })).sorted()
    }
    
    private var filteredLocationSuggestions: [String] {
        newLocation.name.isEmpty ? locationSuggestions : locationSuggestions.filter { $0.localizedCaseInsensitiveContains(newLocation.name) }
    }
    
    var body: some View {
        @State var name: String = item.name
        @State var location: Location = item.location ?? Location(name: "Unknown", color: .white)
        @State var category: Category = item.category ?? Category(name: "")
        @State var background: GridCardBackground = {
            if let imageData = item.imageData, !imageData.isEmpty {
                return .image(imageData)
            } else if let symbol = item.symbol {
                return .symbol(symbol)
            } else {
                return .symbol("questionmark") // fallback symbol
            }
        }()
        @State var symbolColor: Color? = item.symbolColor
        
        NavigationView {
            ZStack {
                RoundedRectangle(cornerRadius: 25.0)
                    .aspectRatio(contentMode: .fill)
                    .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        if case let .image(data) = isEditing ? newBackground : background {
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: geometry.size.height * 0.5)
                                    .mask(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .white, location: 0.0),
                                                .init(color: .white, location: 0.7),
                                                .init(color: .clear, location: 1.0)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: geometry.size.height * 0.5)
                                    )
                            } else {
                                EmptyView()
                            }
                        }
                    }
                }
                
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    .mask(RoundedRectangle(cornerRadius: 25.0)
                        .aspectRatio(contentMode: .fill))
                    .ignoresSafeArea()
                
                VStack {
                    if isEditing {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 8) {
                                TextField("Category", text: $newCategory.name)
                                    .font(.system(.footnote, design: .rounded))
                                    .bold()
                                    .minimumScaleFactor(0.5)
                                    .dynamicTypeSize(.xLarge ... .accessibility5)
                                    .foregroundStyle(.white.opacity(0.95))
                                    .autocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(systemName: "pencil")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if !filteredCategorySuggestions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(filteredCategorySuggestions, id: \.self) { cat in
                                            Button(cat) {
                                                newCategory.name = cat
                                            }
                                            .padding(6)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !category.name.isEmpty {
                        Text(category.name)
                            .font(.system(.footnote, design: .rounded))
                            .bold()
                            .minimumScaleFactor(0.5)
                            .dynamicTypeSize(.xLarge ... .accessibility5)
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if case let .symbol(symbol) = isEditing ? newBackground : background {
                            Image(systemName: symbol)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(isEditing ? (newSymbolColor ?? .accentColor) : (symbolColor ?? .accentColor))
                    } else {
                        Spacer(minLength: 50)
                    }
                    
                    if isEditing {
                        HStack(alignment: .center, spacing: 8) {
                            TextField("Name", text: $newName)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.95))
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.clear, lineWidth: 0)
                                )
                            Image(systemName: "pencil")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
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
                    }
                    
                    if isEditing {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 8) {
                                TextField("Location", text: $newLocation.name)
                                    .font(.system(.callout, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(newLocation.color)
                                    .minimumScaleFactor(0.5)
                                    .dynamicTypeSize(.xLarge ... .accessibility5)
                                    .autocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .onChange(of: newLocation.name) { oldValue, newValue in
                                        if let found = locations.first(where: { $0.name == newValue }) {
                                            newLocation.color = found.color
                                        } else {
                                            newLocation.color = .white
                                        }
                                    }
                                ColorPicker("Location Color", selection: $newLocation.color)
                                    .labelsHidden()
                                    .frame(width: 28, height: 28)
                                Image(systemName: "pencil")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if !filteredLocationSuggestions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(filteredLocationSuggestions, id: \.self) { loc in
                                            Button(loc) {
                                                newLocation.name = loc
                                                if let found = locations.first(where: { $0.name == loc }) {
                                                    newLocation.color = found.color
                                                } else {
                                                    newLocation.color = .white
                                                }
                                            }
                                            .padding(6)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(location.name)
                            .font(.system(.callout, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(location.color)
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
                    }
                    
                    Spacer()
                    
                    // Edit, Delete, and Dismiss buttons
                    HStack {
                        if !isEditing {
                            Button(action: {
                                withAnimation() {
                                    isEditing = true
                                    // Load current item values into edit variables
                                    newName = item.name
                                    newLocation = item.location ?? Location(name: "Unknown", color: .white)
                                    newCategory = item.category ?? Category(name: "")
                                    switch background {
                                    case .symbol(let symbol):
                                        newBackground = .symbol(symbol)
                                        newSymbolColor = symbolColor ?? .accentColor
                                    case .image(let data):
                                        newBackground = .image(data)
                                        newSymbolColor = nil
                                    }
                                }
                            }) {
                                Image(systemName: "pencil")
                                    .frame(width: 25, height: 25)
                                    .bold()
                                    .padding()
                            }
                            .adaptiveGlassButton()
                            .foregroundColor(.blue)
                        } else {
                            Button(action: {
                                withAnimation() {
                                    saveItem(
                                        name: newName,
                                        location: newLocation,
                                        category: newCategory,
                                        background: newBackground,
                                        symbolColor: newSymbolColor
                                    )
                                    isEditing = false
                                    // After saving, update display variables
                                    name = newName
                                    location = newLocation
                                    category = newCategory
                                    background = newBackground
                                    symbolColor = newSymbolColor
                                }
                            }) {
                                Image(systemName: "pencil")
                                    .frame(width: 25, height: 25)
                                    .bold()
                                    .padding()
                            }
                            .adaptiveGlassButton(isEditing)
                            .foregroundColor(.white)
                        }
                        
                        Button(action: {
                            // Delete action stub
                        }) {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: 25, height: 25)
                                .bold()
                                .padding()
                        }
                        .adaptiveGlassButton()
                        .foregroundColor(.red)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Dismiss")
                                .foregroundColor(colorScheme == .light ? .black : .white)
                                .frame(maxWidth: .infinity, minHeight: 25)
                                .bold()
                                .padding()
                        }
                        .adaptiveGlass()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 50)
                }
                .padding(.horizontal, isEditing ? 12 : 24)
                .padding(.vertical)
                .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: .infinity, alignment: .bottom)
            }
        }
        // Only show the picker menu when editing
        .navigationBarItems(trailing:
                                Group {
            if isEditing {
                HStack(spacing: 8) {
                    if case .symbol = newBackground {
                        ColorPicker("Symbol Color", selection: Binding(
                            get: { newSymbolColor ?? .accentColor },
                            set: { newSymbolColor = $0 }
                        ))
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                    }
                    Menu {
                        Button("Change Symbol") {
                            showSymbolPicker = true
                        }
                        Button("Change Image") {
                            showImagePicker = true
                        }
                    } label: {
                        Image(systemName: "photo.circle")
                            .font(.title2)
                    }
                }
            }
        }
        )
        .sheet(isPresented: $showSymbolPicker) {
            // Extract the current symbol from newBackground
            SymbolPickerView(viewBehaviour: .tapWithUnselect, selectedSymbol: Binding(
                get: {
                    if case let .symbol(symbol) = newBackground {
                        return symbol
                    } else {
                        return ""
                    }
                },
                set: { newValue in
                    if !newValue.isEmpty {
                        newBackground = .symbol(newValue)
                        symbolColor = symbolColor ?? .accentColor
                    }
                }
            ))
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: Binding(
                get: {
                    if case let .image(data) = newBackground {
                        return UIImage(data: data)
                    } else {
                        return nil
                    }
                },
                set: { newImage in
                    if let newImage, let data = newImage.pngData() {
                        newBackground = .image(data)
                    }
                }
            ), cropImage: { picked, completion in
                imageToCrop = picked
            })
        }
        .onChange(of: imageToCrop) { _, newValue in
            if let img = newValue, let data = img.pngData() {
                newBackground = .image(data)
                showCropper = true
            }
        }
        .sheet(isPresented: $showCropper) {
            if let img = imageToCrop {
                ImageCropperView(image: img) { cropped in
                    if let data = cropped.pngData() {
                        newBackground = .image(data)
                    }
                    showCropper = false
                    imageToCrop = nil
                }
            }
        }
    }
    
    func saveItem(name: String, location: Location, category: Category, background: GridCardBackground, symbolColor: Color?) {
        // Handle category - create new one if it doesn't exist
        var finalCategory: Category? = nil
        if !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let existingCategory = categories.first(where: { $0.name == category.name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                finalCategory = existingCategory
            } else {
                // Create new category if it doesn't exist
                finalCategory = category
            }
        }
        
        // Handle location - create new one if it doesn't exist
        var finalLocation: Location? = nil
        if !location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let existingLocation = locations.first(where: { $0.name == location.name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                finalLocation = existingLocation
            } else {
                // Create new location if it doesn't exist
                finalLocation = location
            }
        }
        
        // Prepare parameters for Item.update
        var updateImageData: Data? = nil
        var updateSymbol: String? = nil
        var updateSymbolColor: Color? = nil
        
        // Handle background changes
        switch newBackground {
        case let .symbol(symbol):
            updateSymbol = symbol
            updateSymbolColor = symbolColor ?? .accentColor
            updateImageData = nil // Clear image data when switching to symbol
        case let .image(data):
            updateImageData = data
            updateSymbol = nil // Clear symbol when switching to image
            updateSymbolColor = nil
        }
        
        // Use the Item.update function with all parameters
        item.update(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: item.quantity, // Keep existing quantity
            location: finalLocation,
            category: finalCategory,
            imageData: updateImageData,
            symbol: updateSymbol,
            symbolColor: updateSymbolColor
        )
    }
}

#Preview {
    @Previewable @State var item = Item(
        name: "Sample Item",
        location: Location(name: "Sample Location", color: .blue),
        category: Category(name: "Sample Category"),
        imageData: nil,
        symbol: "star.fill",
        symbolColor: .yellow
    )
    
    return ItemView(item: $item)
}

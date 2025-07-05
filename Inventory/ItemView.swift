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
    
    @State private var categoryText: String = ""
    @State private var locationText: String = ""
    
    @State private var newImage: UIImage? = nil
    @State private var imageToCrop: UIImage? = nil
    @State private var newSymbol: String = ""
    @State private var newBackground: GridCardBackground = .symbol("questionmark")
    
    private var categorySuggestions: [String] {
        Array(Set(categories.map { $0.name })).sorted()
    }
    private var filteredCategorySuggestions: [String] {
        categoryText.isEmpty ? categorySuggestions : categorySuggestions.filter { $0.localizedCaseInsensitiveContains(categoryText) }
    }
    
    private var locationSuggestions: [String] {
        Array(Set(locations.map { $0.name })).sorted()
    }
    private var filteredLocationSuggestions: [String] {
        locationText.isEmpty ? locationSuggestions : locationSuggestions.filter { $0.localizedCaseInsensitiveContains(locationText) }
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
                
                GeometryReader { geometry in
                    VStack {
                        if isEditing {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .center, spacing: 8) {
                                    TextField("Category", text: $categoryText)
                                        .onAppear { if categoryText.isEmpty { categoryText = category.name } }
                                        .onChange(of: categoryText) { _, newValue in
                                            if let match = categories.first(where: { $0.name == newValue }) {
                                                category = match
                                            }
                                        }
                                        .font(.system(.footnote, design: .rounded))
                                        .bold()
                                        .foregroundStyle(.ultraThickMaterial)
                                    Image(systemName: "pencil")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                if !filteredCategorySuggestions.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack {
                                            ForEach(filteredCategorySuggestions, id: \.self) { cat in
                                                Button(cat) {
                                                    categoryText = cat
                                                    if let match = categories.first(where: { $0.name == cat }) {
                                                        category = match
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
                        } else if !category.name.isEmpty {
                            Text(category.name)
                                .font(.system(.footnote, design: .rounded))
                                .bold()
                                .foregroundStyle(.ultraThickMaterial)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if case let .symbol(symbol) = isEditing ? newBackground : background {
                            Image(systemName: symbol)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(symbolColor ?? .accentColor)
                                .frame(
                                    width: min(geometry.size.width, geometry.size.height) * 0.35,
                                    height: min(geometry.size.width, geometry.size.height) * 0.40
                                )
                        } else {
                            Spacer(minLength: 50)
                        }
                        
                        if isEditing {
                            HStack(alignment: .center, spacing: 8) {
                                TextField("Name", text: $name)
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
                                    TextField("Location", text: $locationText)
                                        .onAppear { if locationText.isEmpty { locationText = location.name } }
                                        .onChange(of: locationText) { _, newValue in
                                            if let found = locations.first(where: { $0.name == newValue }) {
                                                location = found
                                            }
                                        }
                                        .font(.system(.callout, design: .rounded))
                                        .fontWeight(.medium)
                                        .foregroundColor(location.color)
                                    Image(systemName: "pencil")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                if !filteredLocationSuggestions.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack {
                                            ForEach(filteredLocationSuggestions, id: \.self) { loc in
                                                Button(loc) {
                                                    locationText = loc
                                                    if let found = locations.first(where: { $0.name == loc }) {
                                                        location = found
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
                                        // Copy current background to newBackground
                                        switch background {
                                        case .symbol(let symbol):
                                            newBackground = .symbol(symbol)
                                        case .image(let data):
                                            newBackground = .image(data)
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
                                        saveItem(name: name, location: location, category: category, symbolColor: symbolColor)
                                        isEditing = false
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
                                Label("Dismiss", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                                    .frame(maxWidth: .infinity, minHeight: 25)
                                    .bold()
                                    .padding()
                            }
                            .adaptiveGlassButton()
                        }
                        .frame(maxWidth: .infinity, maxHeight: 50)
                    }
                    .padding()
                    .frame(maxWidth: geometry.size.width * 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            // Only show the picker menu when editing
            .navigationBarItems(trailing:
                                    Group {
                if isEditing {
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
            )
            .sheet(isPresented: $showSymbolPicker) {
                SymbolPickerView(viewBehaviour: .tapWithUnselect, selectedSymbol: $newSymbol)
                    .onDisappear {
                        if !newSymbol.isEmpty {
                            newBackground = .symbol(newSymbol)
                            symbolColor = symbolColor ?? .accentColor
                        }
                    }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $newImage, cropImage: { picked, completion in
                    imageToCrop = picked
                })
            }
            .onChange(of: imageToCrop) { _, newValue in
                if newValue != nil {
                    // Show cropper after image is loaded
                    showCropper = true
                }
            }
            .sheet(isPresented: $showCropper) {
                if let img = imageToCrop {
                    ImageCropperView(image: img) { cropped in
                        newImage = cropped
                        if isEditing, let data = cropped.pngData() {
                            newBackground = .image(data)
                        }
                        showCropper = false
                        imageToCrop = nil
                    }
                }
            }
        }
    }
    
    func saveItem(name: String, location: Location, category: Category, symbolColor: Color?) {
        // Handle category - create new one if it doesn't exist
        var finalCategory: Category? = nil
        if !categoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let existingCategory = categories.first(where: { $0.name == categoryText.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                finalCategory = existingCategory
            } else {
                // Create new category if it doesn't exist
                let newCategory = Category(name: categoryText.trimmingCharacters(in: .whitespacesAndNewlines))
                finalCategory = newCategory
            }
        }
        // Handle location - create new one if it doesn't exist
        var finalLocation: Location? = nil
        if !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let existingLocation = locations.first(where: { $0.name == locationText.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                finalLocation = existingLocation
            } else {
                // Create new location if it doesn't exist
                let newLocation = Location(name: locationText.trimmingCharacters(in: .whitespacesAndNewlines))
                finalLocation = newLocation
            }
        }
        // Prepare parameters for Item.update based on newBackground
        var updateImageData: Data? = nil
        var updateSymbol: String? = nil
        var updateSymbolColor: Color? = nil
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

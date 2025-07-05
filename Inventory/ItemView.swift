//
//  ItemView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI
import SwiftData
import SwiftyCrop

struct ItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
    @State private var orientation = UIDeviceOrientation.unknown
    
    @State private var newName: String = ""
    
    // Editing state variables decoupled from model instances
    @State private var editCategoryName: String = ""
    @State private var editLocationName: String = ""
    @State private var editLocationColor: Color = .white
    @State private var newBackground: GridCardBackground = .symbol("questionmark")
    @State private var newSymbolColor: Color? = nil
    
    // Item display variables - moved out of body
    @State private var name: String = ""
    @State private var location: Location = Location(name: "Unknown", color: .white)
    @State private var category: Category = Category(name: "")
    @State private var background: GridCardBackground = .symbol("questionmark")
    @State private var symbolColor: Color? = nil
    
    // Helper to get suggestions
    private var categorySuggestions: [String] {
        Array(Set(categories.map { $0.name })).sorted()
    }
    
    private var filteredCategorySuggestions: [String] {
        editCategoryName.isEmpty ? categorySuggestions : categorySuggestions.filter { $0.localizedCaseInsensitiveContains(editCategoryName) }
    }
    
    private var locationSuggestions: [String] {
        Array(Set(locations.map { $0.name })).sorted()
    }
    
    private var filteredLocationSuggestions: [String] {
        editLocationName.isEmpty ? locationSuggestions : locationSuggestions.filter { $0.localizedCaseInsensitiveContains(editLocationName) }
    }
    
    private var isLandscape: Bool {
        // Return false for iPad devices to always use portrait layout
        if UIDevice.current.userInterfaceIdiom == .pad {
            return false
        }
        
        return orientation.isLandscape || horizontalSizeClass == .regular
    }
    
    private var toolbarLikeView: some View {
        Group {
            if isEditing {
                HStack(spacing: 0) {
                    if case .symbol = newBackground {
                        ColorPicker("Symbol Color", selection: Binding(
                            get: { newSymbolColor ?? .accentColor },
                            set: { newSymbolColor = $0 }
                        ))
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                        .padding(.horizontal, 4)
                    }
                    Menu {
                        Button("Change Symbol") { showSymbolPicker = true }
                        Button("Change Image") { showImagePicker = true }
                    } label: {
                        Image(systemName: "photo.circle").font(.title2)
                            .adaptiveGlassButton()
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .padding(.horizontal, 4)
                    }
                    .menuStyle(.borderlessButton)
                }
                .frame(height: 44, alignment: .center)
                .adaptiveGlassBackground()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                RoundedRectangle(cornerRadius: 25.0)
                    .aspectRatio(contentMode: .fill)
                    .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .ignoresSafeArea()
                
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
        }
        .onAppear {
            orientation = UIDevice.current.orientation
            initializeDisplayVariables()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientation = UIDevice.current.orientation
        }
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
                SwiftyCropView(
                    imageToCrop: img,
                    maskShape: .square,
                    configuration: SwiftyCropConfiguration(),
                    onComplete: { cropped in
                        if let cropped, let data = cropped.pngData() {
                            newBackground = .image(data)
                        }
                        showCropper = false
                        imageToCrop = nil
                    }
                )
            }
        }
    }
    
    private func initializeDisplayVariables() {
        name = item.name
        location = item.location ?? Location(name: "Unknown", color: .white)
        category = item.category ?? Category(name: "")
        
        if let imageData = item.imageData, !imageData.isEmpty {
            background = .image(imageData)
        } else if let symbol = item.symbol {
            background = .symbol(symbol)
        } else {
            background = .symbol("questionmark")
        }
        
        symbolColor = item.symbolColor
    }
    
    private var portraitLayout: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if case let .image(data) = isEditing ? newBackground : background {
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5)
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
                                .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5)
                            )
                    }
                }
                
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    .mask(RoundedRectangle(cornerRadius: 25.0)
                        .aspectRatio(contentMode: .fill))
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    VStack(alignment: .trailing, spacing: 8) {
                        categorySection
                        toolbarLikeView
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    symbolSection
                    nameSection
                    locationSection
                    Spacer()
                    buttonSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical)
                .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
    
    private var landscapeLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left half - Symbol/Image with toolbar overlay when editing
                ZStack(alignment: .bottomLeading) {
                    if case let .image(data) = isEditing ? newBackground : background {
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width * 0.55, height: geometry.size.height * 0.52)
                                .ignoresSafeArea(.all)
                                .mask(
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .white, location: 0.0),
                                            .init(color: .white, location: 0.7),
                                            .init(color: .clear, location: 0.9)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .ignoresSafeArea(.all)
                                    .frame(width: geometry.size.width * 0.55, height: geometry.size.height * 0.52)
                                )
                        }
                    }
                    
                    if case let .symbol(symbol) = isEditing ? newBackground : background {
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                            .ignoresSafeArea(.all)
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.52)
                        
                        VStack {
                            Spacer()
                            Image(systemName: symbol)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(isEditing ? (newSymbolColor ?? .accentColor) : (symbolColor ?? .accentColor))
                                .frame(maxWidth: min(192, geometry.size.width * 0.3))
                                .padding()
                            Spacer()
                        }
                        .padding(.leading, geometry.safeAreaInsets.leading)
                    }
                    
                    if isEditing {
                        toolbarLikeView
                            .ignoresSafeArea(.all)
                            .padding(.bottom, 8)
                            .padding(.leading, max(geometry.safeAreaInsets.leading, 12))
                    }
                }
                .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                
                // Right half - Content
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        categorySection
                        nameSection
                        locationSection
                    }
                    .padding(.top, 24)
                    
                    Spacer()
                    
                    buttonSection
                        .padding(.bottom, 12)
                }
                .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                .padding(.horizontal, 24)
            }
            .frame(height: geometry.size.height * 1)
        }
    }
    
    // Extract common sections into computed properties
    private var categorySection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        TextField("Category", text: $editCategoryName)
                            .font(.system(.footnote, design: .rounded))
                            .bold()
                            .minimumScaleFactor(0.5)
                            .dynamicTypeSize(.xLarge ... .accessibility5)
                            .foregroundStyle(.white.opacity(0.95))
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        Image(systemName: "pencil")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    if !filteredCategorySuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(filteredCategorySuggestions, id: \.self) { cat in
                                    Button(cat) {
                                        editCategoryName = cat
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
                Text(!category.name.isEmpty ? category.name : "")
                    .font(.system(.footnote, design: .rounded))
                    .bold()
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(.xLarge ... .accessibility5)
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var symbolSection: some View {
        Group {
            if !isLandscape {
                if case let .symbol(symbol) = isEditing ? newBackground : background {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(isEditing ? (newSymbolColor ?? .accentColor) : (symbolColor ?? .accentColor))
                        .frame(maxWidth: 192)
                } else {
                    Spacer(minLength: 50)
                }
            } else {
                EmptyView()
            }
        }
    }
    
    private var nameSection: some View {
        Group {
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
        }
    }
    
    private var locationSection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        TextField("Location", text: $editLocationName)
                            .font(.system(.callout, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(editLocationColor)
                            .minimumScaleFactor(0.5)
                            .dynamicTypeSize(.xLarge ... .accessibility5)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        ColorPicker("Location Color", selection: $editLocationColor)
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
                                        editLocationName = loc
                                        if let found = locations.first(where: { $0.name == loc }) {
                                            editLocationColor = found.color
                                        } else {
                                            editLocationColor = .white
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
        }
    }
    
    private var buttonSection: some View {
        // Edit, Delete, and Dismiss buttons
        HStack {
            if !isEditing {
                Button(action: {
                    withAnimation() {
                        isEditing = true
                        // Load current item values into edit variables
                        newName = item.name
                        editLocationName = item.location?.name ?? "Unknown"
                        editLocationColor = item.location?.color ?? .white
                        editCategoryName = item.category?.name ?? ""
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
                        // Construct Category and Location based on edited names and colors
                        var finalCategory: Category? = nil
                        let trimmedCategoryName = editCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedCategoryName.isEmpty {
                            if let existingCategory = categories.first(where: { $0.name == trimmedCategoryName }) {
                                finalCategory = existingCategory
                            } else {
                                finalCategory = Category(name: trimmedCategoryName)
                            }
                        }
                        
                        var finalLocation: Location? = nil
                        let trimmedLocationName = editLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedLocationName.isEmpty {
                            if let existingLocation = locations.first(where: { $0.name == trimmedLocationName }) {
                                finalLocation = existingLocation
                            } else {
                                finalLocation = Location(name: trimmedLocationName, color: editLocationColor)
                            }
                        }
                        
                        // Save item with updated details
                        saveItem(
                            name: newName,
                            category: finalCategory,
                            location: finalLocation,
                            background: newBackground,
                            symbolColor: newSymbolColor
                        )
                        
                        isEditing = false
                        
                        // Update display variables from saved data
                        name = newName
                        category = finalCategory ?? Category(name: "")
                        location = finalLocation ?? Location(name: "Unknown", color: .white)
                        background = newBackground
                        symbolColor = newSymbolColor
                    }
                }) {
                    Image(systemName: "pencil")
                        .frame(width: 25, height: 25)
                        .bold()
                        .padding()
                }
                .adaptiveGlassEditButton(isEditing)
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
            .adaptiveGlassButton()
        }
        .frame(maxWidth: .infinity, maxHeight: 50)
    }
    
    func saveItem(name: String, category: Category?, location: Location?, background: GridCardBackground, symbolColor: Color?) {
        // Store references to old category and location for cleanup
        let oldCategory = item.category
        let oldLocation = item.location
        
        // Prepare parameters for Item.update
        var updateImageData: Data? = nil
        var updateSymbol: String? = nil
        var updateSymbolColor: Color? = nil
        
        // Handle background changes
        switch background {
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
            location: location,
            category: category,
            imageData: updateImageData,
            symbol: updateSymbol,
            symbolColor: updateSymbolColor
        )
        
        // Clean up orphaned entities after the update
        oldCategory?.deleteIfEmpty(from: modelContext)
        oldLocation?.deleteIfEmpty(from: modelContext)
        
        // Save the context to persist changes
        try? modelContext.save()
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

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
    
    @Binding var item: Item
    
    // State variables for UI
    @State var isEditing: Bool = false
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropper: Bool = false
    @State private var imageToCrop: UIImage? = nil
    @State private var orientation = UIDeviceOrientation.unknown
    
    // Item display variables - Original values
    @State private var name: String = ""
    @State private var quantity: Int = 0
    @State private var location: Location = Location(name: "Unknown", color: .white)
    @State private var category: Category = Category(name: "")
    @State private var background: GridCardBackground = .symbol("questionmark")
    @State private var symbolColor: Color? = nil
    
    // Item editing variables
    @State private var editName: String = ""
    @State private var editCategoryName: String = ""
    @State private var editLocationName: String = ""
    @State private var editLocationColor: Color = .white
    @State private var editBackground: GridCardBackground = .symbol("questionmark")
    @State private var editSymbolColor: Color? = nil
    
    // Helper to get suggestions
    private var locationSuggestions: [String] {
        Array(Set(locations.map { $0.name })).sorted()
    }
    
    private var filteredLocationSuggestions: [String] {
        editLocationName.isEmpty ? locationSuggestions : locationSuggestions.filter { $0.localizedCaseInsensitiveContains(editLocationName) }
    }
    
    private var categorySuggestions: [String] {
        Array(Set(categories.map { $0.name })).sorted()
    }
    
    private var filteredCategorySuggestions: [String] {
        editCategoryName.isEmpty ? categorySuggestions : categorySuggestions.filter { $0.localizedCaseInsensitiveContains(editCategoryName) }
    }
    
    // Helper to determine if the device is in landscape mode
    private var isLandscape: Bool {
        return orientation.isLandscape || horizontalSizeClass == .regular
    }
    
    // Helper to determine if Liquid Glass design is available
    let usesLiquidGlass: Bool = {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()
    
    var swiftyCropConfiguration: SwiftyCropConfiguration {
        SwiftyCropConfiguration(
            maxMagnificationScale: 4.0,
            maskRadius: 130,
            cropImageCircular: false,
            rotateImage: false,
            rotateImageWithButtons: true,
            usesLiquidGlassDesign: usesLiquidGlass,
            zoomSensitivity: 4.0,
            rectAspectRatio: 4/3,
            texts: SwiftyCropConfiguration.Texts(
                cancelButton: "Cancel",
                interactionInstructions: "",
                saveButton: "Save"
            ),
            fonts: SwiftyCropConfiguration.Fonts(
                cancelButton: Font.system(size: 12),
                interactionInstructions: Font.system(size: 14),
                saveButton: Font.system(size: 12)
            ),
            colors: SwiftyCropConfiguration.Colors(
                cancelButton: Color.red,
                interactionInstructions: Color.white,
                saveButton: Color.blue,
                background: Color.gray
            )
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                RoundedRectangle(cornerRadius: 25.0)
                    .aspectRatio(contentMode: .fill)
                    .foregroundStyle(LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .ignoresSafeArea()
                
                
                if UIDevice.current.userInterfaceIdiom == .pad {
                    iPadLayout
                } else if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
        }
        .onAppear {
            if !isValidItem(item) {
                dismiss()
            }
            
            orientation = UIDevice.current.orientation
            initializeDisplayVariables()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientation = UIDevice.current.orientation
        }
        .sheet(isPresented: $showSymbolPicker) {
            // Extract the current symbol from editBackground
            SymbolPickerView(viewBehaviour: .tapWithUnselect, selectedSymbol: Binding(
                get: {
                    if case let .symbol(symbol) = editBackground {
                        return symbol
                    } else {
                        return ""
                    }
                },
                set: { newValue in
                    if !newValue.isEmpty {
                        editBackground = .symbol(newValue)
                        symbolColor = symbolColor ?? .accentColor
                    }
                }
            ))
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: Binding(
                get: {
                    if case let .image(data) = editBackground {
                        return UIImage(data: data)
                    } else {
                        return nil
                    }
                },
                set: { newImage in
                    if let newImage, let data = newImage.pngData() {
                        editBackground = .image(data)
                    }
                }
            ), cropImage: { picked, completion in
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
                SwiftyCropView(
                    imageToCrop: img,
                    maskShape: .square,
                    configuration: swiftyCropConfiguration,
                    onComplete: { cropped in
                        if let cropped, let data = cropped.pngData() {
                            editBackground = .image(data)
                        }
                        showCropper = false
                        imageToCrop = nil
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    private func initializeDisplayVariables() {
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
    }
    
    private var portraitLayout: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if case let .image(data) = isEditing ? editBackground : background {
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
                                ).frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5)
                            )
                    }
                }
                
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    .mask(RoundedRectangle(cornerRadius: 25.0)
                        .aspectRatio(contentMode: .fill))
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            categorySection
                            Spacer()
                            quantitySection
                        }
                        toolbarView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    symbolSection
                    nameSection
                    locationSection
                    Spacer()
                    buttonSection
                }
                .padding(.top, 8)
                .padding(.vertical)
                .padding(.horizontal, 20)
                .frame(maxWidth: geometry.size.width * 0.5)
            }
        }
    }
    
    private var iPadLayout: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if case let .image(data) = isEditing ? editBackground : background {
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width * 0.65, height: geometry.size.height * 0.6)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white, location: 0.7),
                                        .init(color: .clear, location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ).frame(width: geometry.size.width * 0.65, height: geometry.size.height * 0.6)
                            )
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .white, location: 0.1),
                                        .init(color: .white, location: 0.9),
                                        .init(color: .clear, location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ).frame(width: geometry.size.width * 0.65, height: geometry.size.height * 0.6)
                            )
                    }
                }
                
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    .mask(RoundedRectangle(cornerRadius: 25.0)
                        .aspectRatio(contentMode: .fill))
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            categorySection
                            Spacer()
                            quantitySection
                        }
                        toolbarView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    symbolSection
                    nameSection
                    locationSection
                    Spacer()
                    buttonSection
                }
                .padding(.top, 8)
                .padding(.vertical, max(24, min(geometry.size.height * 0.06 + (max(0, 520 - geometry.size.width) * 0.18), 120)))
                .padding(.horizontal, max(12, min(geometry.size.width * 0.10, 48)))
                .frame(maxWidth: geometry.size.width, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
    
    private var landscapeLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left half - Symbol/Image with toolbar overlay when editing
                ZStack(alignment: .bottomLeading) {
                    if case let .image(data) = isEditing ? editBackground : background {
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
                    
                    if case let .symbol(symbol) = isEditing ? editBackground : background {
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                            .ignoresSafeArea(.all)
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.52)
                        
                        VStack {
                            Spacer()
                            Image(systemName: symbol)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(isEditing ? (editSymbolColor ?? .accentColor) : (symbolColor ?? .accentColor))
                                .frame(maxWidth: min(192, geometry.size.width * 0.3))
                                .padding()
                            Spacer()
                        }
                        .padding(.leading, geometry.safeAreaInsets.leading)
                    }
                    
                    if isEditing {
                        toolbarView
                            .ignoresSafeArea(.all)
                            .padding(.bottom, 8)
                            .padding(.leading, max(geometry.safeAreaInsets.leading, 12))
                    }
                }
                .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                
                // Right half - Content
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            categorySection
                            Spacer()
                            quantitySection
                        }
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
            .frame(height: geometry.size.height)
        }
    }
    
    private var toolbarView: some View {
        Group {
            if isEditing {
                HStack(spacing: 0) {
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
                    if case .symbol = editBackground {
                        ColorPicker("Symbol Color", selection: Binding(
                            get: { editSymbolColor ?? .accentColor },
                            set: { editSymbolColor = $0 }
                        ))
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                        .padding(.horizontal, 4)
                    }
                }
                .frame(height: 44, alignment: .center)
                .adaptiveGlassBackground()
            }
        }
    }
    
    // Extract common sections into computed properties
    private var categorySection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Category", text: $editCategoryName)
                            .font(.system(.callout, design: .rounded))
                            .bold()
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white.opacity(0.95))
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .frame(minHeight: 12)
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
                if !category.name.isEmpty {
                    Text(category.name)
                        .font(.system(.callout, design: .rounded))
                        .bold()
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(8)
                        .frame(minHeight: 32)
                        .adaptiveGlassBackground(tintStrength: 0.5)
                }
            }
        }
    }
    
    private var quantitySection: some View {
        Group {
            if quantity > 0 {
                Text(String(quantity))
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(8)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 32)
                    .adaptiveGlassBackground(tintStrength: 0.5)
            }
        }
    }
    
    private var symbolSection: some View {
        Group {
            if !isLandscape {
                if case let .symbol(symbol) = isEditing ? editBackground : background {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(isEditing ? (editSymbolColor ?? .accentColor) : (symbolColor ?? .accentColor))
                        .frame(maxWidth: .infinity, maxHeight: 256, alignment: .center)
                } else {
                    Spacer(minLength: 64)
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
                    Image(systemName: "pencil")
                        .foregroundColor(.white.opacity(0.7))
                    
                    TextField("Name", text: $editName)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .minimumScaleFactor(0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.clear, lineWidth: 0)
                        )
                }
            } else {
                Text(name)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.95))
                    .minimumScaleFactor(0.5)
            }
        }
    }
    
    private var locationSection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Location", text: $editLocationName)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(editLocationColor)
                            .minimumScaleFactor(0.5)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        ColorPicker("Location Color", selection: $editLocationColor)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
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
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
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
                        editName = item.name
                        editLocationName = item.location?.name ?? "The Void"
                        editLocationColor = item.location?.color ?? .gray
                        editCategoryName = item.category?.name ?? ""
                        switch background {
                        case .symbol(let symbol):
                            editBackground = .symbol(symbol)
                            editSymbolColor = symbolColor ?? .accentColor
                        case .image(let data):
                            editBackground = .image(data)
                            editSymbolColor = nil
                        }
                    }
                }) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 25, minHeight: 25)
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
                            name: editName,
                            quantity: quantity,
                            location: finalLocation,
                            category: finalCategory,
                            background: editBackground,
                            symbolColor: editSymbolColor
                        )
                        
                        isEditing = false
                        
                        // Update display variables from saved data
                        name = editName
                        quantity = max(quantity, 0) // Ensure quantity is non-negative
                        location = finalLocation ?? Location(name: "The Void", color: .gray)
                        category = finalCategory ?? Category(name: "")
                        background = editBackground
                        symbolColor = editSymbolColor
                    }
                }) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, minHeight: 25)
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
            
            if !isEditing {
                Button(action: {
                    dismiss()
                }) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.titleOnly)
                        .frame(maxWidth: .infinity, minHeight: 25)
                        .bold()
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundColor(colorScheme == .light ? .black : .white)
            } else {
                Button(action: {
                    dismiss()
                }) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: 25, minHeight: 25)
                        .bold()
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundColor(colorScheme == .light ? .black : .white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 50)
    }
    
    private func isValidItem(_ item: Item) -> Bool {
        // Example: Check if the item exists in the database or has a valid ID/Name
        return !item.name.isEmpty
    }
    
    private func saveItem(name: String, quantity: Int, location: Location?, category: Category?, background: GridCardBackground, symbolColor: Color?) {
        // Store references to old category and location for cleanup
        let oldLocation = item.location
        let oldCategory = item.category
        
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
            quantity: max(quantity, 0), // Ensure quantity is non-negative
            location: location,
            category: category,
            imageData: updateImageData,
            symbol: updateSymbol,
            symbolColor: updateSymbolColor
        )
        
        // Clean up orphaned entities after the update
        oldLocation?.deleteIfEmpty(from: modelContext)
        oldCategory?.deleteIfEmpty(from: modelContext)
        
        // Save the context to persist changes
        try? modelContext.save()
    }
}

#Preview {
    @Previewable @State var item = Item(
        name: "Sample Item",
        quantity: 1,
        location: Location(name: "Sample Location", color: .blue),
        category: Category(name: "Sample Category"),
        imageData: nil,
        symbol: "star.fill",
        symbolColor: .yellow
    )
    
    return ItemView(item: $item)
}


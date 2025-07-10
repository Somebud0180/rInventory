//
//  ItemView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//
//  View for displaying and editing an individual item in the inventory.

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
    @Query private var items: [Item]
    
    @Binding var item: Item
    
    // State variables for UI
    @State var isEditing: Bool = false
    @State private var isKeyboardVisible: Bool = false
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
    @State private var editQuantity: Int = 0
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
    
    private var roundedRectGradient: LinearGradient {
        switch background {
        case .image:
            return LinearGradient(colors: [.black.opacity(0.5), .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .symbol:
            if colorScheme == .dark {
                return LinearGradient(colors: [.black.opacity(0.9), .gray.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                return LinearGradient(colors: [.black.opacity(0.5), .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    
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
                if case let .image(data) = background, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .blur(radius: 44)
                }
                
                RoundedRectangle(cornerRadius: 25.0)
                    .aspectRatio(contentMode: .fill)
                    .foregroundStyle(roundedRectGradient)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation (.smooth) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation (.smooth) {
                isKeyboardVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            withAnimation (.smooth) {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }?
                    .endEditing(true)
                orientation = UIDevice.current.orientation
            }
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
            let adjustedWidth = geometry.size.width * (isKeyboardVisible ? 0.8 : 0.5)
            let adjustedHeight = geometry.size.width * (isKeyboardVisible ? 0.8 : 0.5)
            ZStack(alignment: .top) {
                ItemBackgroundView(
                    background: isEditing ? editBackground : background,
                    symbolColor: isEditing ? editSymbolColor : symbolColor,
                    frame: CGSize(width: adjustedWidth, height: adjustedHeight),
                    mask: AnyView(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: 0.8),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .blur(radius: 12)
                        .frame(width: adjustedWidth, height: adjustedHeight)
                    )
                )
                
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            categorySection
                            Spacer()
                            quantitySection
                        }
                        toolbarView
                    }
                    
                    Spacer(minLength: 128)
                    nameSection
                    locationSection
                    quantityStepperSection
                    Spacer()
                    buttonSection
                }
                .padding(.top, 12)
                .padding(.vertical)
                .padding(.horizontal, 20)
                .ignoresSafeArea(.keyboard)
                .frame(width: adjustedWidth)
            }
        }
    }
    
    private var landscapeLayout: some View {
        GeometryReader { geometry in
            let adjustedHeight = geometry.size.width * (isKeyboardVisible ? 0.25 : 0.5)
            HStack(spacing: 0) {
                // Left half - Symbol/Image with toolbar overlay when editing
                ZStack(alignment: .bottomLeading) {
                    ItemBackgroundView(
                        background: isEditing ? editBackground : background,
                        symbolColor: isEditing ? editSymbolColor : symbolColor,
                        frame: CGSize(width: geometry.size.width * 0.5, height: adjustedHeight),
                        mask: AnyView(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white, location: 0.2),
                                    .init(color: .white, location: 0.8),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .blur(radius: 12)
                            .frame(width: geometry.size.width * 0.45, height: adjustedHeight)
                        )
                    )
                    .ignoresSafeArea(.all)
                    
                    if isEditing {
                        toolbarView
                            .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: geometry.size.width * 0.45, maxHeight: adjustedHeight)
                
                // Right half - Content
                ScrollView {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center) {
                                categorySection
                                Spacer()
                                quantitySection
                            }
                            nameSection
                            locationSection
                            quantityStepperSection
                        }
                        
                        Spacer(minLength: 128)
                        buttonSection
                    }
                    .padding(.top, 12)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: geometry.size.width * 0.55, maxHeight: adjustedHeight)
            }
            .padding(.leading, geometry.safeAreaInsets.leading * 0.25)
            .padding(.trailing, geometry.safeAreaInsets.trailing * 0.25)
            .frame(height: geometry.size.height)
        }
    }
    
    private var iPadLayout: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ItemBackgroundView(
                    background: isEditing ? editBackground : background,
                    symbolColor: isEditing ? editSymbolColor : symbolColor,
                    frame: CGSize(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5),
                    mask: AnyView(
                        // Vertical Gradient
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.2),
                                .init(color: .white, location: 0.8),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .blur(radius: 12)
                        .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5)
                        // Horizontal Gradient
                            .mask(LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white, location: 0.2),
                                    .init(color: .white, location: 0.8),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                                .blur(radius: 12)
                                .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.5))
                    )
                )
                
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            categorySection
                            Spacer()
                            quantitySection
                        }
                        toolbarView
                    }
                    
                    Spacer(minLength: 128)
                    nameSection
                    locationSection
                    quantityStepperSection
                    Spacer()
                    buttonSection
                }
                .padding(.vertical, max(24, min(geometry.size.height * 0.06 + (max(0, 500 - geometry.size.width) * 0.18), 120)))
                .padding(.horizontal, max(12, min(geometry.size.width * 0.10, 48)))
            }
        }
    }
    
    /// View for displaying either an image or a symbol background with a mask.
    private struct ItemBackgroundView: View {
        let background: GridCardBackground
        let symbolColor: Color?
        let frame: CGSize
        let mask: AnyView
        
        var body: some View {
            switch background {
            case .image(let data):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .frame(width: frame.width, height: frame.height)
                        .mask(mask)
                }
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(symbolColor ?? .accentColor)
                    .padding(.top, 32)
                    .frame(width: frame.width * 0.75, height: frame.height)
                    .mask(mask)
            }
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
                .frame(height: 44, alignment: .leading)
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
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextField("Category", text: $editCategoryName)
                            .font(.system(.callout, design: .rounded))
                            .bold()
                            .foregroundStyle(.white.opacity(0.95))
                            .minimumScaleFactor(0.5)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .frame(minHeight: 22)
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
                        .minimumScaleFactor(0.5)
                        .font(.system(.callout, design: .rounded))
                        .bold()
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
            if isEditing {
                if editQuantity > 0 {
                    Menu {
                        Button("Disable Quantity") {
                            // MARK: - Identify best save behavior for editQuantity (save immediately or on save button press)
                            updateQuantity(editQuantity)
                            editQuantity = 0
                        }
                    } label: {
                        Text(String(editQuantity))
                            .minimumScaleFactor(0.5)
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(8)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 32)
                            .adaptiveGlassBackground(tintStrength: 0.5)
                    }
                } else {
                    Menu {
                        Button("Enable Quantity") { editQuantity = max(1, quantity) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .minimumScaleFactor(0.5)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(7) // to match padding of Text
                            .frame(minWidth: 32, minHeight: 32)
                            .adaptiveGlassButton(tintStrength: 0.5)

                    }
                    .menuStyle(.borderlessButton)
                }
            } else {
                if quantity > 0 {
                    Text(String(quantity))
                        .minimumScaleFactor(0.5)
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(8)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 32)
                        .adaptiveGlassBackground(tintStrength: 0.5)
                }
            }
        }
    }
    
    private var nameSection: some View {
        Group {
            if isEditing {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white.opacity(0.7))
                    
                    TextField("Name", text: $editName)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.95))
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.clear, lineWidth: 0)
                        )
                }
            } else {
                Text(name)
                    .minimumScaleFactor(0.5)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
    }
    
    private var locationSection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextField("Location", text: $editLocationName)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(editLocationColor)
                            .minimumScaleFactor(0.5)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        ColorPicker("Location Color", selection: $editLocationColor)
                            .labelsHidden()
                            .padding(.trailing, 12)
                            .frame(width: 24, height: 24)
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
                    .minimumScaleFactor(0.5)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(location.color)
                    .lineLimit(2)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .adaptiveGlassBackground(tintStrength: 0.5)
            }
        }
    }
    
    private var quantityStepperSection: some View {
        Group {
            if isEditing {
                if editQuantity > 0 {
                    Stepper(value: $editQuantity, in: 1...1000, step: 1) {
                        Text("Quantity: \(editQuantity)")
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(.leading, 4)
                    .padding(8)
                    .adaptiveGlassBackground(tintStrength: 0.5)
                }
            } else {
                if quantity > 0 {
                    Stepper(value: $quantity, in: 1...1000, step: 1) {
                        Text("Quantity: \(quantity)")
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .onChange(of: quantity) {
                        updateQuantity(quantity)
                    }
                    .padding(.leading, 4)
                    .padding(8)
                    .adaptiveGlassBackground(tintStrength: 0.5)
                }
            }
        }
        .padding(.vertical, 4)
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
                        editQuantity = item.quantity
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
                .foregroundStyle(.blue)
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
                        
                        // Save item with updated details using Item instance method
                        item.updateItem(
                            name: editName,
                            quantity: editQuantity,
                            location: finalLocation,
                            category: finalCategory,
                            background: editBackground,
                            symbolColor: editSymbolColor,
                            context: modelContext
                        )
                        
                        isEditing = false
                        
                        // Update display variables from saved data
                        name = editName
                        quantity = max(editQuantity, 0) // Ensure quantity is non-negative
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
                .foregroundStyle(.white)
            }
            
            Button(action: {
                // Delete action using Item instance method
                item.deleteItem(context: modelContext, items: items)
                dismiss()
            }) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 25, height: 25)
                    .bold()
                    .padding()
            }
            .adaptiveGlassButton()
            .foregroundStyle(.red)
            
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
                .foregroundStyle(colorScheme == .light ? .black : .white)
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
                .foregroundStyle(colorScheme == .light ? .black : .white)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: 50)
    }
    
    private func updateQuantity(_ newValue: Int) {
        if newValue >= 0 {
            quantity = newValue
            item.updateItem(quantity: newValue, context: modelContext)
        }
    }
    
    private func isValidItem(_ item: Item) -> Bool {
        // Example: Check if the item exists in the database or has a valid ID/Name
        return !item.name.isEmpty
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


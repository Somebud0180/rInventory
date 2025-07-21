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
import PhotosUI

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
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropper: Bool = false
    @State private var imageToCrop: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    // Item display variables - Original values
    @State private var name: String = ""
    @State private var quantity: Int = 0
    @State private var location: Location = Location(name: "Unknown", color: .white)
    @State private var category: Category = Category(name: "")
    @State private var background: ItemCardBackground = .symbol("questionmark")
    @State private var symbolColor: Color? = nil
    
    // Item editing variables
    @State private var editName: String = ""
    @State private var editQuantity: Int = 0
    @State private var editCategoryName: String = ""
    @State private var editLocationName: String = ""
    @State private var editLocationColor: Color = .white
    @State private var editBackground: ItemCardBackground = .symbol("questionmark")
    @State private var editSymbolColor: Color? = nil
    
    // Helper to determine if the device is in landscape mode
    private var isLandscape: Bool {
        return horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    if case let .image(data) = background {
                        AsyncItemImage(imageData: data)
                            .scaledToFill()
                            .ignoresSafeArea(.all)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            .blur(radius: 44)
                    }
                    
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        iPadLayout(geometry)
                    } else if isLandscape {
                        landscapeLayout(geometry)
                            .ignoresSafeArea(.keyboard)
                    } else {
                        portraitLayout(geometry)
                            .ignoresSafeArea(.keyboard)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .if(UIDevice.current.userInterfaceIdiom != .pad) { view in
                view.ignoresSafeArea(.keyboard)
            }
            .background(backgroundGradient)
        }
        .onAppear {
            initializeDisplayVariables()
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    imageToCrop = uiImage
                }
            }
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
                        selectedPhotoItem = nil
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    private var backgroundGradient: AnyView {
        return AnyView(
            ZStack {
                if case let .image(data) = background, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 44)
                }
                
                Rectangle()
                    .foregroundStyle(backgroundLinearGradient)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            })
    }
    
    private var backgroundLinearGradient: LinearGradient {
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
    
    private func portraitLayout(_ geometry: GeometryProxy) -> some View {
        return ZStack(alignment: .top) {
            ItemBackgroundView(
                background: isEditing ? editBackground : background,
                symbolColor: isEditing ? editSymbolColor : symbolColor,
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
                    .frame(maxHeight: geometry.size.height * 0.45)
                )
            )
            .frame(maxHeight: geometry.size.height * 0.48)
            
            
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    categorySection
                    Spacer()
                    quantitySection
                }
                
                // Wrap in ZStack to overlay toolbar on top of content
                ZStack(alignment: .topLeading) {
                    toolbarView
                    
                    VStack(alignment: .leading) {
                        Spacer()
                            .frame(maxHeight: 256)
                        
                        nameSection
                        locationSection
                            .padding(.bottom, 12)
                        quantityStepperSection
                        Spacer()
                        buttonSection
                    }
                }
            }
            .padding(.top, 6)
            .padding(.vertical)
            .padding(.horizontal, 20)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func landscapeLayout(_ geometry: GeometryProxy) -> some View {
        return HStack(spacing: 0) {
            // Left half - Symbol/Image with toolbar overlay when editing
            ZStack(alignment: .bottomLeading) {
                ItemBackgroundView(
                    background: isEditing ? editBackground : background,
                    symbolColor: isEditing ? editSymbolColor : symbolColor,
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
                        .frame(width: geometry.size.width * 0.46, height: geometry.size.height)
                    )
                )
                
                if isEditing {
                    toolbarView
                        .padding(.bottom, 8)
                }
            }
            .frame(width: geometry.size.width * 0.48, height: geometry.size.height)
            
            // Right half - Content
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        categorySection
                        Spacer()
                        quantitySection
                    }.padding(.bottom, 12)
                    
                    nameSection
                    locationSection
                        .padding(.bottom, 12)
                    quantityStepperSection
                }
                
                Spacer()
                buttonSection
            }
            .padding(.top, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: geometry.size.width * 0.52, maxHeight: geometry.size.height)
        }
        .padding(.leading, geometry.safeAreaInsets.leading * 0.25)
        .padding(.trailing, geometry.safeAreaInsets.trailing * 0.25)
        .frame(height: geometry.size.height)
    }
    
    private func iPadLayout(_ geometry: GeometryProxy) -> some View {
        return ZStack(alignment: .bottom) {
            // Background - either image or symbol, with a gradient mask
            ZStack(alignment: .bottomLeading) {
                ItemBackgroundView(
                    background: isEditing ? editBackground : background,
                    symbolColor: isEditing ? editSymbolColor : symbolColor,
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
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    )
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            
            // Card - contains all the item details and controls
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        categorySection
                        Spacer()
                        quantitySection
                    }
                    
                    HStack() {
                        nameSection
                        if isEditing {
                            toolbarView
                        }
                    }
                    locationSection
                    quantityStepperSection
                    buttonSection
                        .padding(.vertical, 6)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 25))
            }
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 25))
            .frame(maxWidth: geometry.size.width * 0.65, maxHeight: geometry.size.height * 0.45, alignment: .bottom)
            .padding(.bottom, 12 - geometry.safeAreaInsets.bottom * 0.26)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    /// View for displaying either an image or a symbol background with a mask.
    private struct ItemBackgroundView: View {
        let background: ItemCardBackground
        let symbolColor: Color?
        let mask: AnyView
        
        var body: some View {
            switch background {
            case .image(let data):
                AsyncItemImage(imageData: data)
                    .scaledToFill()
                    .ignoresSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .mask(mask)
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(.all)
                    .padding(.top, 24)
                    .padding(22)
                    .foregroundStyle(symbolColor ?? .accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .mask(mask)
            }
        }
    }
    
    private var toolbarView: some View {
        Group {
            if isEditing {
                HStack(spacing: 0) {
                    Button(action: { showSymbolPicker = true }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .adaptiveGlassButton()
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .padding(.horizontal, 4)
                    }
                    .accessibilityLabel("Change Symbol")
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.circle")
                            .font(.title2)
                            .adaptiveGlassButton()
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .padding(.horizontal, 4)
                    }
                    .accessibilityLabel("Change Image")
                    if case .symbol = editBackground {
                        ColorPicker("Symbol Color", selection: Binding(
                            get: { editSymbolColor ?? .accentColor },
                            set: { editSymbolColor = $0 }
                        ), supportsOpacity: false)
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
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white.opacity(0.95))
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .frame(minHeight: 22)
                    }
                    filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $editCategoryName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !category.name.isEmpty {
                    Text(category.name)
                        .font(.system(.callout, design: .rounded))
                        .bold()
                        .lineLimit(2)
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
            if isEditing {
                if editQuantity > 0 {
                    Menu {
                        Button("Disable Quantity") {
                            // MARK: - Identify best save behavior for editQuantity (save immediately or on save button press)
                            editQuantity = 0
                        }
                    } label: {
                        Text(String(editQuantity))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(8)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 32)
                            .adaptiveGlassBackground(tintStrength: 0.5)
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    Menu {
                        Button("Enable Quantity") { editQuantity = max(1, quantity) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
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
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
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
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .minimumScaleFactor(0.5)
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
                            .minimumScaleFactor(0.75)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        ColorPicker("Location Color", selection: $editLocationColor, supportsOpacity: false)
                            .labelsHidden()
                            .padding(.trailing, 12)
                            .frame(width: 32, height: 32)
                    }
                    filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $editLocationName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(location.name)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(location.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
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
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .minimumScaleFactor(0.75)
                    .padding(.leading, 8)
                    .padding(8)
                    .adaptiveGlassBackground(tintStrength: 0.5, shape: usesLiquidGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12.0)))
                }
            } else {
                if quantity > 0 {
                    Stepper(value: $quantity, in: 0...1000, step: 1) {
                        Text("Quantity: \(quantity)")
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundStyle(.white.opacity(0.95))
                            .minimumScaleFactor(0.75)
                    }
                    .onChange(of: quantity) {
                        updateQuantity(quantity)
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .minimumScaleFactor(0.75)
                    .padding(.leading, 8)
                    .padding(8)
                    .adaptiveGlassBackground(tintStrength: 0.5, shape: usesLiquidGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12.0)))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var buttonSection: some View {
        // Edit, Delete, and Dismiss buttons
        HStack {
            if !isEditing {
                Button(action: editItem) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 25, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundStyle(.blue)
            } else {
                Button(action: saveItem) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassEditButton(isEditing)
                .foregroundStyle(.white)
            }
            
            Button(action: {
                // Delete action using Item instance method
                item.deleteItem(context: modelContext)
                dismiss()
            }) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: 24, minHeight: 24)
                    .bold()
                    .minimumScaleFactor(0.5)
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
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundStyle(.white)
            } else {
                Button(action: {
                    dismiss()
                }) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: 24, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: 50)
    }
    
    private func editItem() {
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
    }
    
    private func saveItem() {
        withAnimation() {
            // Save item with updated details using Item instance method
            item.updateItem(
                name: editName,
                quantity: editQuantity,
                locationName: editLocationName,
                locationColor: editLocationColor,
                categoryName: editCategoryName,
                background: editBackground,
                symbolColor: editSymbolColor,
                context: modelContext
            )
            
            isEditing = false
            
            // Update display variables from saved data
            name = editName
            quantity = max(editQuantity, 0) // Ensure quantity is non-negative
            location = Location(name: editLocationName, color: editLocationColor)
            category = Category(name: editCategoryName)
            background = editBackground
            symbolColor = editSymbolColor
        }
    }
    
    private func updateQuantity(_ newValue: Int) {
        if newValue >= 0 {
            quantity = newValue
            item.updateItem(quantity: newValue, context: modelContext)
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
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

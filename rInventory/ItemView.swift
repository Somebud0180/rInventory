//
//  ItemView.swift
//  rInventory
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
    
    // State variables for Editing UI
    private enum ItemField: Hashable {
        case name, category, location
    }
    
    @State var isEditing: Bool = false
    @State private var isCollapsed: Bool = false
    @FocusState private var focusedField: ItemField?
    @State private var animateFocused: ItemField? = nil
    
    // State variables for UI
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
    
    /// Helper to determine if the device is in landscape mode
    private var isLandscape: Bool {
        return horizontalSizeClass == .regular
    }
    
    /// Helper to determine if the device is an iPad
    private var isPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        if case let .image(data) = background {
                            AsyncItemImage(imageData: data)
                                .scaledToFill()
                                .ignoresSafeArea(.all)
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                .blur(radius: 44)
                        }
                        
                        if isPad{
                            iPadBackground(geometry)
                                .ignoresSafeArea(.keyboard)
                        } else if isLandscape {
                                landscapeLayout(geometry)
                                    .ignoresSafeArea(.keyboard)
                                    .preferredColorScheme(.dark)
                        } else {
                            portraitLayout(geometry)
                                .ignoresSafeArea(.keyboard)
                                .preferredColorScheme(.dark)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea(.keyboard)
                .background(backgroundGradient)
                
                if isPad {
                    GeometryReader { geometry in
                        iPadLayout(geometry)
                    }
                }
            }
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
        .onChange(of: focusedField) {
            withAnimation() {
                animateFocused = focusedField
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
        let secondaryColor = (colorScheme == .dark) ? Color.black.opacity(0.9) : Color.gray.opacity(0.9)
        return LinearGradient(colors: [.accentDark.opacity(0.9), secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                            .frame(maxHeight: isEditing ? 296 : 320)
                        
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
        return VStack() {
            Spacer()
            
            // Card - contains all the item details and controls
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if !isEditing {
                        Button(action: { withAnimation { isCollapsed.toggle() }}) {
                            Image(systemName: "chevron.up")
                                .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                                .frame(maxWidth: geometry.size.width, alignment: .center)
                        }
                    }
                    
                    if isCollapsed {
                        HStack(alignment: .center) {
                            nameSection
                            Spacer()
                            quantitySection
                        }
                        buttonSection
                            .padding(.vertical, 6)
                    } else {
                        if animateFocused == nil || animateFocused == .category {
                            HStack(alignment: .center) {
                                categorySection
                                Spacer()
                                quantitySection
                            }
                        }
                        
                        if animateFocused == nil || animateFocused == .name {
                            HStack() {
                                nameSection
                                if isEditing {
                                    toolbarView
                                }
                            }
                        }
                        
                        if animateFocused == nil || animateFocused == .location {
                            locationSection
                        }
                        
                        if animateFocused == nil {
                            quantityStepperSection
                        }

                        buttonSection
                            .padding(.vertical, 6)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32))
            }
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 32))
            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.45, alignment: .bottom)
        }
        .padding(4)
        .padding(.bottom, -(geometry.safeAreaInsets.bottom * 0.2))
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func iPadBackground(_ geometry: GeometryProxy) -> some View {
        VStack {
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
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.75)
                )
            )
            .frame(width: geometry.size.width, height: geometry.size.height * 0.75)
            
            Spacer()
        }
        .frame(maxHeight: geometry.size.height)
        .padding(.trailing, -geometry.safeAreaInsets.bottom)
    }
    
    /// View for displaying either an image or a symbol background with a mask.
    private struct ItemBackgroundView: View {
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    .padding(.top,
                             (UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular)
                             ? 16
                             : 64)
                    .padding(.horizontal, 22)
                    .foregroundStyle(symbolColor ?? .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                            .foregroundStyle(.secondary)
                        
                        TextField("Category", text: $editCategoryName)
                            .focused($focusedField, equals: .category)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .minimumScaleFactor(0.5)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .frame(minHeight: 22)
                        
                        Button(action: { editCategoryName = "" }, label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        })
                    }
                    filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $editCategoryName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !category.name.isEmpty {
                    Text(category.name)
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
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
                            .padding(8)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 32)
                            .adaptiveGlassBackground(tintStrength: 0.5, shape: editQuantity < 10 ? AnyShape(Circle()) : AnyShape(Capsule()))
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
                        .padding(8)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 32)
                        .adaptiveGlassBackground(tintStrength: 0.5, shape: quantity < 10 ? AnyShape(Circle()) : AnyShape(Capsule()))
                }
            }
        }
    }
    
    private var nameSection: some View {
        Group {
            if isEditing {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                    
                    TextField("Name", text: $editName)
                        .focused($focusedField, equals: .name)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
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
            }
        }
    }
    
    private var locationSection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                        
                        TextField("Location", text: $editLocationName)
                            .focused($focusedField, equals: .location)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .minimumScaleFactor(0.75)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                        
                        Button(action: { editLocationName = "" }, label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        })
                        
                        ColorPicker("Location Color", selection: $editLocationColor, supportsOpacity: false)
                            .labelsHidden()
                            .padding(.trailing, 12)
                            .frame(width: 32, height: 32)
                            .onChange(of: editLocationName) { oldValue, newValue in
                                if let found = locations.first(where: { $0.name == newValue }) {
                                    editLocationColor = found.color
                                } else {
                                    editLocationColor = .white
                                }
                            }
                    }
                    filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $editLocationName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(location.name)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .adaptiveGlassBackground(tintStrength: 0.5, tintColor: location.color)
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
                            .minimumScaleFactor(0.75)
                    }
                    .minimumScaleFactor(0.75)
                    .padding(.leading, 8)
                    .padding(8)
                    .adaptiveGlassBackground(tintStrength: 0.5, shape: usesLiquidGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12.0)))
                }
            } else {
                if quantity > 0 {
                    Stepper(value: $quantity, in: 1...1000, step: 1) {
                        Text("Quantity: \(quantity)")
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .minimumScaleFactor(0.75)
                    }
                    .onChange(of: quantity) {
                        updateQuantity(quantity)
                    }
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
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer {
                    buttonContent
                }
            } else {
                buttonContent
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: 50)
    }
    
    private var buttonContent: some View {
        HStack {
            if !isEditing {
                Button(action: editItem) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.accentLight)
                        .frame(minWidth: 25, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassButton()
                .foregroundStyle(.accent)
            } else {
                Button(action: saveItem) {
                    Label("Save Edits", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding()
                }
                .adaptiveGlassEditButton(isEditing)
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
                .foregroundStyle(colorScheme == .dark ? .white : .black)
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
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            }
        }
    }
    
    private func editItem() {
        withAnimation() {
            isEditing = true
            isCollapsed = false
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
        DispatchQueue.main.async {
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
        }
        
        withAnimation() {
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


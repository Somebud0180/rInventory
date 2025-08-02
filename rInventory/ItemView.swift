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
import MijickCamera

/// View for displaying either an image or a symbol background with a mask.
struct ItemBackgroundView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    let background: ItemCardBackground
    let symbolColor: Color?
    let mask: AnyView
    
    var body: some View {
        switch background {
        case .image(let data):
            if UIDevice.current.userInterfaceIdiom == .pad {
                AsyncItemImage(imageData: data)
                    .scaledToFit()
                    .ignoresSafeArea(.all)
                    .mask(mask)
            } else {
                AsyncItemImage(imageData: data)
                    .scaledToFill()
                    .ignoresSafeArea(.all)
                    .mask(mask)
            }
        case .symbol(let symbol):
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(symbolColor ?? .white)
                .mask(mask)
                .ignoresSafeArea(.all)
                .padding(.top,
                         (UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular)
                         ? 16
                         : 64)
                .padding(.horizontal, 22)
        }
    }
}

struct ItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @ObservedObject var syncEngine: CloudKitSyncEngine
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
    @State private var animateFocused: ItemField? = nil
    @FocusState private var focusedField: ItemField?
    
    // State variables for UI
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropper: Bool = false
    
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
                        
                        if isPad {
                            iPadBackground(geometry)
                                .ignoresSafeArea(.keyboard)
                        } else if isLandscape {
                            if #available(iOS 26, *) {
                                GlassEffectContainer {
                                    landscapeLayout(geometry)
                                        .ignoresSafeArea(.keyboard)
                                        .preferredColorScheme(.dark)
                                }
                            } else {
                                landscapeLayout(geometry)
                                    .ignoresSafeArea(.keyboard)
                                    .preferredColorScheme(.dark)
                            }
                        } else {
                            if #available(iOS 26, *) {
                                GlassEffectContainer {
                                    portraitLayout(geometry)
                                        .ignoresSafeArea(.keyboard)
                                        .preferredColorScheme(.dark)
                                }
                            } else {
                                portraitLayout(geometry)
                                    .ignoresSafeArea(.keyboard)
                                    .preferredColorScheme(.dark)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea(.keyboard)
                .background(backgroundGradient)
                
                if isPad {
                    GeometryReader { geometry in
                        if #available(iOS 26, *) {
                            GlassEffectContainer {
                                iPadLayout(geometry)
                            }
                        } else {
                            iPadLayout(geometry)
                        }
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
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selection: Binding(
                get: {
                    if case let .image(data) = editBackground {
                        return UIImage(data: data)
                    } else {
                        return nil
                    }
                },
                set: { newImage in
                    if let newImage {
                        imageToCrop = newImage
                    }
                }
            ))
        }
        .fullScreenCover(isPresented: $showCamera) {
            MCamera()
                .setCameraOutputType(.photo)
                .setAudioAvailability(false)
                .setCameraScreen(CustomCameraScreen.init)
                .onImageCaptured { image, controller in
                    imageToCrop = image
                    controller.reopenCameraScreen()
                    showCamera = false
                }
                .setCloseMCameraAction {
                    showCamera = false
                }
                .startSession()
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
                        imageToCrop = nil                    }
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
                    toolbarSection
                    
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
                
                toolbarSection
                    .padding(.bottom, 8)
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
                VStack(alignment: .leading, spacing: 4) {
                    if !isEditing {
                        Button(action: { withAnimation { isCollapsed.toggle() }}) {
                            Image(systemName: "chevron.up")
                                .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                                .frame(maxWidth: geometry.size.width, alignment: .center)
                        }
                    }
                    
                    if (animateFocused == nil || animateFocused == .category) && !isCollapsed {
                        HStack {
                            categorySection
                            Spacer()
                            if isEditing {
                                toolbarSection
                            } else {
                                quantitySection
                            }
                        }
                        
                    }
                    
                    if animateFocused == nil || animateFocused == .name {
                        HStack() {
                            nameSection
                        }
                    }
                    
                    if (animateFocused == nil || animateFocused == .location) && !isCollapsed {
                        locationSection
                    }
                    
                    if animateFocused == nil && !isCollapsed {
                        HStack {
                            quantityStepperSection
                            if isEditing{
                                Spacer()
                                quantitySection
                            }
                        }
                    }
                    
                    buttonSection
                        .padding(.vertical, 6)
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
                    .mask(
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
                    )
                )
            )
            
            Spacer()
        }
        .frame(maxHeight: geometry.size.height)
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
            }
        )
    }
    
    private var backgroundLinearGradient: LinearGradient {
        let secondaryColor = (colorScheme == .dark) ? Color.black.opacity(0.9) : Color.gray.opacity(0.9)
        return LinearGradient(colors: [.accentDark.opacity(0.9), secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var toolbarSection: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    toolbarContent
                }
            } else {
                toolbarContent
            }
        }
    }
    
    private var toolbarContent: some View {
        Group {
            if isEditing {
                HStack(spacing: 0) {
                    Button(action: { showSymbolPicker = true }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .adaptiveGlassButton()
                            .frame(width: 36, height: 36)
                            .padding(.horizontal, 4)
                    }
                    .accessibilityLabel("Change Symbol")
                    
                    Menu {
                        Button(action: {showImagePicker = true}) {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        
                        Button(action: {showCamera = true}) {
                            Label("Take Photo", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "photo")
                            .font(.title2)
                            .adaptiveGlassButton()
                            .frame(width: 36, height: 36)
                            .padding(.horizontal, 4)
                    }
                    .menuStyle(.borderlessButton)
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
                .foregroundStyle(colorScheme == .light ? .black : .white)
                .adaptiveGlassBackground()
            }
        }
    }
    
    // Extract common sections into computed properties
    private var categorySection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                        
                        TextField("Category", text: $editCategoryName)
                            .focused($focusedField, equals: .category)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .minimumScaleFactor(0.75)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .onSubmit {
                                editCategoryName = editCategoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .onChange(of: editCategoryName) { oldValue, newValue in
                                if newValue.count >= 40 {
                                    editCategoryName = String(newValue.prefix(40))
                                }
                            }
                        
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
                        .minimumScaleFactor(0.75)
                        .padding(8)
                        .adaptiveGlassBackground(tintStrength: 0.5)
                }
            }
        }
    }
    
    private var quantitySection: some View {
        Group {
            if isEditing {
                Menu {
                    Button(editQuantity == 0 ? "Store Quantity" : "Don't Store Quantity") {
                        if editQuantity == 0 {
                            editQuantity = max(1, quantity)
                        } else {
                            editQuantity = 0
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .minimumScaleFactor(0.75)
                        .padding(8)
                        .frame(minWidth: isPad ? 44 : 32, minHeight: isPad ? 44 : 32)
                        .adaptiveGlassButton(tintStrength: 0.5)
                }
                .menuStyle(.borderlessButton)
            } else {
                if quantity > 0 {
                    Text(String(quantity))
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
                        .minimumScaleFactor(0.75)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .onSubmit {
                            editName = editName.prefix(32).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .onChange(of: editName) { oldValue, newValue in
                            if newValue.count >= 32 {
                                editName = String(newValue.prefix(32))
                            }
                        }
                }
            } else {
                Text(name)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
    
    private var locationSection: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
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
                            .onSubmit {
                                editLocationName = editLocationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .onChange(of: editLocationName) { oldValue, newValue in
                                if newValue.count >= 40 {
                                    editLocationName = String(newValue.prefix(40))
                                }
                            }
                        
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
        let quantityVar = isEditing ? editQuantity : quantity
        let quantityBind = isEditing ? $editQuantity : $quantity
        return Group {
            if quantityVar > 0 {
                Stepper(value: quantityBind, in: 1...1000, step: 1) {
                    Text("Quantity: \(quantityVar)")
                        .font(.system(.body, design: .rounded))
                        .bold()
                }
                .onChange(of: quantity) {
                    // Only run updateQuantity for real quantity
                    Task {
                        await updateQuantity(quantity)
                    }
                }
                .minimumScaleFactor(0.75)
                .padding(.leading, 8)
                .padding(8)
                .adaptiveGlassBackground(tintStrength: 0.5, shape: usesLiquidGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12.0)))
                .padding(.vertical, 4)
            }
        }
    }
    
    private var buttonSection: some View {
        HStack {
            if !isEditing {
                editButton
            } else {
                saveButton
            }

            deleteButton

            dismissButton
        }
        .frame(maxWidth: .infinity, maxHeight: 50)
    }

    // MARK: - Button Helpers
    private var editButton: some View {
        Button(action: editItem) {
            Label("Save Edits", systemImage: "pencil")
                .labelStyle(.iconOnly)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.accentLight)
                .bold()
                .frame(maxWidth: 24, minHeight: 24)
                .padding()
        }
        .adaptiveGlassButton()
    }

    private var saveButton: some View {
        Button(action: { Task { await saveItem() }}) {
            Label("Save Edits", systemImage: "pencil")
                .labelStyle(.titleAndIcon)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .bold()
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding()
        }
        .adaptiveGlassEditButton(isEditing)
    }

    private var deleteButton: some View {
        Button(action: {
            Task {
                await item.deleteItem(context: modelContext, cloudKitSyncEngine: syncEngine)
            }
            dismiss()
        }) {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.red)
                .bold()
                .frame(maxWidth: 24, minHeight: 24)
                .padding()
        }
        .adaptiveGlassButton()
    }

    private var dismissButton: some View {
        Button(action: { dismiss() }) {
            Label("Dismiss", systemImage: "xmark")
                .if(isEditing) { $0.labelStyle(.iconOnly) }
                .if(!isEditing) { $0.labelStyle(.titleOnly) }
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .minimumScaleFactor(0.5)
                .bold()
                .frame(maxWidth: isEditing ? 24 : .infinity, minHeight: 24)
                .padding()
        }
        .adaptiveGlassButton()
    }
    
    // MARK: - Functional Helpers
    private func editItem() {
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
        
        withAnimation() {
            isEditing = true
            isCollapsed = false
        }
    }
    
    private func saveItem() async {
        // Save item with updated details using Item instance method
        await item.updateItem(
            name: editName,
            quantity: editQuantity,
            locationName: editLocationName,
            locationColor: editLocationColor,
            categoryName: editCategoryName,
            background: editBackground,
            symbolColor: editSymbolColor,
            context: modelContext,
            cloudKitSyncEngine: syncEngine
        )
        
        // Update display variables from saved data
        name = editName
        quantity = max(editQuantity, 0) // Ensure quantity is non-negative
        location = Location(name: editLocationName, color: editLocationColor)
        category = Category(name: editCategoryName)
        background = editBackground
        symbolColor = editSymbolColor
        
        withAnimation() {
            isEditing = false
        }
    }
    
    private func updateQuantity(_ newValue: Int) async {
        if newValue >= 0 {
            quantity = newValue
            await item.updateItem(quantity: newValue, context: modelContext, cloudKitSyncEngine: syncEngine)
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
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: InventoryApp.sharedModelContainer.mainContext)
    @Previewable @State var item = Item(
        name: "Sample Item",
        quantity: 1,
        location: Location(name: "Sample Location", color: .blue),
        category: Category(name: "Sample Category"),
        imageData: nil,
        symbol: "star.fill",
        symbolColor: .yellow
    )
    
    return ItemView(syncEngine:syncEngine, item: $item)
}


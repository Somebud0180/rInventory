//
//  ItemCreationView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view allows users to create a new item in the inventory.

import SwiftUI
import SwiftData
import SwiftyCrop
import PhotosUI
import MijickCamera

struct ItemCreationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @Query private var categories: [Category]
    @Query private var locations: [Location]
    
    // State variables for UI
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropper: Bool = false
    
    // Item creation variables
    @State private var name: String = "New Item"
    @State private var quantity: Int = 1
    @State private var isQuantityEnabled: Bool = false
    @State private var locationName: String = ""
    @State private var locationColor: Color = .white
    @State private var categoryName: String = ""
    @State private var background: ItemCardBackground = .symbol("square.grid.2x2")
    @State private var symbolColor: Color = .white
    
    // Helper to determine if Liquid Glass design is available
    let usesLiquidGlass: Bool = {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()
    
    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .center, spacing: 12) {
                    itemCard(
                        name: name,
                        quantity: isQuantityEnabled ? quantity : 0,
                        location: Location(name: locationName, color: locationColor),
                        category: Category(name: categoryName),
                        background: background,
                        symbolColor: symbolColor,
                        colorScheme: colorScheme,
                        largeFont: true,
                        showCounterForSingleItems: AppDefaults.shared.showCounterForSingleItems
                    )
                    .frame(maxWidth: 250, maxHeight: 250, alignment: .center)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("New Item", text: $name)
                            .font(.largeTitle.bold())
                            .padding(.bottom, 4)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .onSubmit {
                                name = name.prefix(32).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .onChange(of: name) { oldValue, newValue in
                                if newValue.count >= 32 {
                                    name = String(newValue.prefix(40))
                                }
                            }
                        
                        HStack(alignment: .center, spacing: 12) {
                            TextField("Location", text: $locationName)
                                .font(.body)
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
                                .onSubmit {
                                    locationName = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                .onChange(of: locationName) { oldValue, newValue in
                                    if newValue.count >= 40 {
                                        locationName = String(newValue.prefix(40))
                                    }
                                    
                                    if let found = locations.first(where: { $0.name == newValue }) {
                                        locationColor = found.color
                                    } else {
                                        locationColor = .white
                                    }
                                }
                            
                            Button(action: { locationName = "" }, label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.secondary)
                            }).padding(.horizontal, 4)
                            
                            if !locationName.isEmpty {
                                ColorPicker("Location Color", selection: $locationColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: 32, height: 32)
                            }
                        }
                        
                        filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $locationName)
                        
                        Divider()
                            .ignoresSafeArea(edges: .trailing)
                        
                        HStack {
                            TextField("Category", text: $categoryName)
                                .font(.body)
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
                                .onSubmit {
                                    categoryName = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                .onChange(of: categoryName) { oldValue, newValue in
                                    if newValue.count >= 40 {
                                        categoryName = String(newValue.prefix(40))
                                    }
                                }
                            
                            Button(action: { categoryName = "" }, label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.secondary)
                            }).padding(.horizontal, 4)
                        }
                        
                        filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $categoryName)
                    }
                }
                
                Section(header: Text("Quantity")) {
                    Toggle(isOn: $isQuantityEnabled) {
                        Text("Store Quantity")
                    }
                    Stepper(value: $quantity, in: 1...100, step: 1) {
                        Text("Quantity: \(quantity)")
                            .foregroundStyle(isQuantityEnabled ? .primary : .secondary)
                    }.disabled(!isQuantityEnabled)
                }
                
                Section(header: Text("Select an icon")) {
                    HStack {
                        Menu {
                            Button(action: {showImagePicker = true}) {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                            
                            Button(action: {showCamera = true}) {
                                Label("Take Photo", systemImage: "camera")
                            }
                        } label: {
                            Text(imageButtonTitle)
                        }
                        
                        Spacer()
                        
                        if case .image(let data) = background, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            showSymbolPicker = true
                        } label: {
                            if case .symbol(let symbol) = background, !symbol.isEmpty {
                                HStack(spacing: 8) {
                                    Text("Change Symbol: ")
                                    Image(systemName: symbol)
                                    Spacer()
                                }
                            } else {
                                Text("Select a Symbol")
                            }
                        }
                        
                        if case .symbol = background {
                            ColorPicker("Symbol Color", selection: $symbolColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 24, height: 24)
                                .padding(.leading, 12)
                        }
                    }
                }
                
                Section {
                    Button("Save Item") { saveItem() }
                        .disabled(name.isEmpty || locationName.isEmpty || !isBackgroundValid)
                }
            }
            .padding(.top, -24)
            .navigationBarTitle("Create an Item", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Item") { saveItem() }
                        .disabled(name.isEmpty || locationName.isEmpty || !isBackgroundValid)
                }
            }
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerView(viewBehaviour: .tapWithUnselect, selectedSymbol: Binding(
                get: {
                    if case .symbol(let symbol) = background { return symbol } else { return "" }
                },
                set: { newSymbol in
                    background = .symbol(newSymbol)
                }
            ))
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selection: Binding(
                get: {
                    if case let .image(data) = background {
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
                .setCameraOutputTypeSwitchVisibility(false)
                .setAudioAvailability(false)
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
                            background = .image(data)
                        }
                        showCropper = false
                        imageToCrop = nil
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    private func saveItem() {
        Item.saveItem(
            name: name,
            quantity: isQuantityEnabled ? quantity : 0,
            locationName: locationName,
            locationColor: locationColor,
            categoryName: categoryName,
            background: background,
            symbolColor: symbolColor,
            context: modelContext
        )
        dismiss()
    }
    
    // MARK: - Computed Properties
    
    private var imageButtonTitle: String {
        if case .image = background {
            return "Change Image"
        } else {
            return "Select Image"
        }
    }
    
    private var isBackgroundValid: Bool {
        switch background {
        case .symbol(let symbol):
            return !symbol.isEmpty
        case .image(let data):
            return data == data
        }
    }
}
#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}

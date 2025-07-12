//
//  ItemCreationView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/3/25.
//
//  This view allows users to create a new item in the inventory.

import SwiftUI
import SwiftData
import SwiftyCrop

struct ItemCreationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @Query private var categories: [Category]
    @Query private var locations: [Location]
    
    
    // State variables for UI
    @State private var showSymbolPicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropper: Bool = false
    @State private var imageToCrop: UIImage? = nil
    
    // Item creation variables
    @State private var name: String = "New Item"
    @State private var quantity: Int = 1
    @State private var isQuantityEnabled: Bool = false
    @State private var locationName: String = ""
    @State private var locationColor: Color = .white
    @State private var categoryName: String = ""
    @State private var background: GridCardBackground = .symbol("square.grid.2x2")
    @State private var symbolColor: Color = .accentColor
    
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
            Form {
                gridCard(
                    name: name,
                    quantity: isQuantityEnabled ? quantity : 0,
                    location: Location(name: locationName, color: locationColor),
                    category: Category(name: categoryName),
                    background: background,
                    symbolColor: symbolColor,
                    colorScheme: colorScheme,
                    largeFont: true
                )
                .frame(maxWidth: .infinity, maxHeight: 250, alignment: .center)
                .listRowSeparator(.hidden)
                
                VStack(alignment: .leading, spacing: 12) {
                    TextField("New Item", text: $name)
                        .font(.largeTitle.bold())
                        .padding(.bottom, 4)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                    
                    HStack(alignment: .center, spacing: 12) {
                        TextField("Location", text: $locationName)
                            .font(.body)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .onChange(of: locationName) { oldValue, newValue in
                                if let found = locations.first(where: { $0.name == newValue }) {
                                    locationColor = found.color
                                } else {
                                    locationColor = .white
                                }
                            }
                        
                        if !locationName.isEmpty {
                            ColorPicker("Location Color", selection: $locationColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 32, height: 32)
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $locationName)
                    
                }
                
                VStack {
                    HStack(alignment: .center, spacing: 12) {
                        TextField("Category", text: $categoryName)
                            .font(.body)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    
                    filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $categoryName)
                }
                
                Section(header: Text("Quantity")) {
                    Toggle(isOn: $isQuantityEnabled) {
                        Text("Enable Quantity")
                    }
                    Stepper(value: $quantity, in: 1...100, step: 1) {
                        Text("Quantity: \(quantity)")
                            .foregroundStyle(isQuantityEnabled ? .primary : .secondary)
                    }.disabled(!isQuantityEnabled)
                }
                
                Section(header: Text("Select an icon")) {
                    HStack {
                        if case .image(let data) = background, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button(imageButtonTitle) {
                            showImagePicker = true
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
            ImagePicker(image: Binding(
                get: {
                    if case let .image(data) = background {
                        return UIImage(data: data)
                    } else {
                        return nil
                    }
                },
                set: { newImage in
                    if let newImage, let data = newImage.pngData() {
                        background = .image(data)
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

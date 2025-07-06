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
    @State private var quantity: Int = 0
    @State private var locationName: String = ""
    @State private var locationColor: Color = .white
    @State private var categoryName: String = ""
    @State private var background: GridCardBackground = .symbol("square.grid.2x2")
    @State private var symbolColor: Color = .accentColor
    
    // Helper to get suggestions
    private var categorySuggestions: [String] {
        Array(Set(categories.map { $0.name })).sorted()
    }
    
    private var filteredCategorySuggestions: [String] {
        categoryName.isEmpty ? categorySuggestions : categorySuggestions.filter { $0.localizedCaseInsensitiveContains(categoryName) }
    }
    
    private var locationSuggestions: [String] {
        Array(Set(locations.map { $0.name })).sorted()
    }
    
    private var filteredLocationSuggestions: [String] {
        locationName.isEmpty ? locationSuggestions : locationSuggestions.filter { $0.localizedCaseInsensitiveContains(locationName) }
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
            zoomSensitivity: 2.0,
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
        NavigationView {
            Form {
                gridCard(
                    name: name,
                    quantity: quantity,
                    location: Location(name: locationName, color: locationColor),
                    category: Category(name: categoryName),
                    background: background,
                    symbolColor: symbolColor,
                    colorScheme: colorScheme
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
                    
                    if !filteredLocationSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(filteredLocationSuggestions, id: \.self) { loc in
                                    Button(loc) {
                                        locationName = loc
                                        if let found = locations.first(where: { $0.name == loc }) {
                                            locationColor = found.color
                                        } else {
                                            locationColor = .white
                                        }
                                    }
                                    .padding(6)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    Divider().padding(.top, 4)
                    
                    HStack(alignment: .center, spacing: 12) {
                        TextField("Category", text: $categoryName)
                            .font(.body)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    if !filteredCategorySuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(filteredCategorySuggestions, id: \.self) { cat in
                                    Button(cat) {
                                        categoryName = cat
                                    }
                                    .padding(6)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
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
                    Button("Save") {
                        saveItem(name: name, locationName: locationName, locationColor: locationColor, categoryName: categoryName, background: background, symbolColor: symbolColor)
                    }
                    .disabled(name.isEmpty || locationName.isEmpty || !isBackgroundValid)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
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
            }
        }
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
    
    // MARK: - Helper Methods
    
    private func saveItem(name: String, locationName: String, locationColor: Color, categoryName: String, background: GridCardBackground, symbolColor: Color) {
        let location = findOrCreateLocation(locationName: locationName, locationColor: locationColor)
        let category = findOrCreateCategory(categoryName: categoryName)
        let (imageData, symbol, symbolColor) = extractBackgroundData(background: background)
        
        let newItem = Item(
            name: name,
            quantity: max(quantity, 0), // Ensure quantity is non-negative
            location: location,
            category: category,
            imageData: imageData,
            symbol: symbol,
            symbolColor: symbolColor
        )
        
        modelContext.insert(newItem)
        dismiss()
    }
    
    private func findOrCreateLocation(locationName: String, locationColor: Color) -> Location {
        if let existingLocation = locations.first(where: { $0.name == locationName }) {
            return existingLocation
        } else {
            let newLocation = Location(name: locationName, color: locationColor)
            modelContext.insert(newLocation)
            return newLocation
        }
    }
    
    private func findOrCreateCategory(categoryName: String) -> Category? {
        guard !categoryName.isEmpty else { return nil }
        
        if let existingCategory = categories.first(where: { $0.name == categoryName }) {
            return existingCategory
        } else {
            let newCategory = Category(name: categoryName)
            modelContext.insert(newCategory)
            return newCategory
        }
    }
    
    private func extractBackgroundData(background: GridCardBackground) -> (Data?, String?, Color?) {
        switch background {
        case let .symbol(symbol):
            return (nil, symbol, symbolColor)
        case let .image(data):
            return (data, nil, nil)
        }
    }
}

#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}

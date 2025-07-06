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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Form fields
    @State private var name: String = "New Item"
    @State private var locationName: String = ""
    @State private var locationColor: Color = .white
    @State private var categoryName: String = ""
    @State private var image: UIImage? = nil
    @State private var showImagePicker: Bool = false
    @State private var symbol: String = ""
    @State private var symbolColor: Color = .accentColor
    @State private var showSymbolPicker: Bool = false
    @State private var showCropper: Bool = false
    @State private var imageToCrop: UIImage? = nil
    
    // Fetch existing locations and categories
    @Query private var categories: [Category]
    @Query private var locations: [Location]
    
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
                    location: Location(name: locationName, color: locationColor),
                    category: Category(name: categoryName),
                    background: image != nil ? .image(image!.jpegData(compressionQuality: 0.8)!) : .symbol(symbol),
                    symbolColor: symbol.isEmpty ? nil : symbolColor,
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
                            ColorPicker("", selection: $locationColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
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
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button(image == nil ? "Select Image" : "Change Image") {
                            showImagePicker = true
                        }
                    }
                    
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            showSymbolPicker = true
                        } label: {
                            if !symbol.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: symbol)
                                    Text(formattedSymbolName(symbol))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Pick a Symbol")
                            }
                        }
                        
                        Spacer()
                        
                        if !symbol.isEmpty {
                            ColorPicker("", selection: $symbolColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        }
                    }
                }
                
                Section {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(name.isEmpty || locationName.isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $image, cropImage: { picked, completion in
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
                            image = cropped
                            showCropper = false
                            imageToCrop = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SymbolPickerView(viewBehaviour: .tapWithUnselect, selectedSymbol: $symbol)
            }
        }
    }
    
    private func saveItem() {
        // Find or create Location
        let location: Location
        if let existingLoc = locations.first(where: { $0.name == locationName }) {
            location = existingLoc
        } else {
            location = Location(name: locationName, color: locationColor)
            modelContext.insert(location)
        }
        // Find or create Category
        var category: Category? = nil
        if !categoryName.isEmpty {
            if let existingCat = categories.first(where: { $0.name == categoryName }) {
                category = existingCat
            } else {
                let newCat = Category(name: categoryName)
                modelContext.insert(newCat)
                category = newCat
            }
        }
        // Prepare image data
        let imageData = image?.jpegData(compressionQuality: 0.8)
        let newItem = Item(name: name, location: location, category: category, imageData: imageData, symbol: symbol.isEmpty ? nil : symbol, symbolColor: symbol.isEmpty ? nil : symbolColor)
        modelContext.insert(newItem)
        dismiss()
    }
    
    private func formattedSymbolName(_ symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

#Preview {
    ItemCreationView()
        .modelContainer(for: Item.self)
        .modelContainer(for: Category.self)
        .modelContainer(for: Location.self)
}

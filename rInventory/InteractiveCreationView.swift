//
//  InteractiveCreationView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/17/25.
//

import SwiftUI
import SwiftData
import SwiftyCrop
import Playgrounds

struct InteractiveCreationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Query(sort: \Location.name, order: .forward) private var locations: [Location]
    @Query(sort: \Category.name, order: .forward) private var categories: [Category]
    
    private enum progress: Int {
        case itemSymbol
        case itemName
        case itemQuantity
        case itemLocation
        case itemCategory
        case reviewAndSave
    }
    
    @Binding var isPresented: Bool
    @State private var creationProgress: progress = .itemSymbol
    @State private var lastProgress: progress = .itemSymbol
    @State private var isForward: Bool = true
    @State private var animateGradient: Bool = false
    @State private var showCamera: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropView: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var showSymbolPicker: Bool = false
    @State private var showDismissAlert: Bool = false
    
    // Final Item Variables
    @State private var background: ItemCardBackground = .symbol("")
    @State private var symbolColor: Color = .white
    @State private var name: String = ""
    @State private var isQuantityEnabled: Bool = false
    @State private var quantity: Int = 1
    @State private var locationName: String = ""
    @State private var locationColor: Color = .white
    @State private var categoryName: String = ""
    
    private var gradientColors: [Color] {
        colorScheme == .light ? [.accentLight, .accentDark] : [.accentDark, .accentLight]
    }
    
    private var textFieldFormatter: Formatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 100
        return formatter
    }

    /// Helper to determine if the device is an iPhone in landscape mode
    private var isPhoneLandscape: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ZStack {
                animatedBackground
                if isPhoneLandscape {
                    HStack(alignment: .center) {
                        VStack {
                            progressBar
                            Group {
                                switch creationProgress {
                                case .itemSymbol:
                                    itemSymbol
                                case .itemName:
                                    itemName
                                case .itemQuantity:
                                    itemQuantity
                                case .itemLocation:
                                    itemLocation
                                case .itemCategory:
                                    itemCategory
                                case .reviewAndSave:
                                    reviewAndSave
                                }
                            }
                            .foregroundStyle(.white)
                            .transition(.asymmetric(
                                insertion: .move(edge: isForward ? .trailing : .leading),
                                removal: .move(edge: isForward ? .leading : .trailing)
                            ))
                            .frame(maxWidth: 400, maxHeight: 800)
                            .padding(16)
                        }
                        Divider()
                        VStack {
                            Spacer()
                            landscapeButtonsView
                            Spacer()
                        }
                        .frame(maxWidth: 300)
                        .padding(.trailing, 24)
                    }
                } else {
                    VStack {
                        progressBar
                        Group {
                            switch creationProgress {
                            case .itemSymbol:
                                itemSymbol
                            case .itemName:
                                itemName
                            case .itemQuantity:
                                itemQuantity
                            case .itemLocation:
                                itemLocation
                            case .itemCategory:
                                itemCategory
                            case .reviewAndSave:
                                reviewAndSave
                            }
                        }
                        .foregroundStyle(.white)
                        .transition(.asymmetric(
                            insertion: .move(edge: isForward ? .trailing : .leading),
                            removal: .move(edge: isForward ? .leading : .trailing)
                        ))
                        .frame(maxWidth: 400, maxHeight: 800)
                        .padding(16)
                    }
                }
            }
            .alert("Are you sure you want to exit? Your progress will be lost.", isPresented: $showDismissAlert) {
                Button("Exit", role: .destructive) { isPresented = false }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: creationProgress) { oldValue, newValue in
                lastProgress = oldValue
                isForward = newValue.rawValue > oldValue.rawValue
            }
        }
    // Buttons for landscape mode
    private var landscapeButtonsView: some View {
        VStack(spacing: 16) {
            switch creationProgress {
            case .itemSymbol:
                symbolButtons
            case .itemName:
                nameButtons
            case .itemQuantity:
                quantityButtons
            case .itemLocation:
                locationButtons
            case .itemCategory:
                categoryButtons
            case .reviewAndSave:
                reviewButtons
            }
        }
    }

    // Extracted buttons for each step
    private var symbolButtons: some View {
        Group {
            if case .symbol(let symbol) = background, symbol.isEmpty {
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        Label("Camera", systemImage: "camera.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: { showImagePicker = true }) {
                        Label("Photo Library", systemImage: "photo.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: { showSymbolPicker = true }) {
                        Label("Symbol", systemImage: "star.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
                VStack(spacing: 16) {
                    Button(action: {
                        isForward = true
                        withAnimation { creationProgress = .itemName }
                    }) {
                        Label("Looks Good!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: {
                        isForward = false
                        withAnimation { background = .symbol("") }
                    }) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            }
        }
    }

    private var nameButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .itemQuantity }
            }) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(name.isEmpty ? .gray : (colorScheme == .dark ? .white : .black))
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(tintColor: name.isEmpty ? .gray : .white, interactive: !name.isEmpty)
            .disabled(name.isEmpty)
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemSymbol; name = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }

    private var quantityButtons: some View {
        Group {
            if !isQuantityEnabled {
                VStack(spacing: 16) {
                    Button(action: {
                        isForward = true
                        withAnimation { isQuantityEnabled = true }
                    }) {
                        Label("Yes", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: {
                        isForward = true
                        withAnimation { isQuantityEnabled = false; creationProgress = .itemLocation }
                    }) {
                        Label("No", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: {
                        isForward = false
                        withAnimation { creationProgress = .itemName; quantity = 1 }
                    }) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
                VStack(spacing: 16) {
                    Button(action: {
                        isForward = true
                        withAnimation { creationProgress = .itemLocation }
                    }) {
                        Label("Next", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: {
                        isForward = false
                        withAnimation { isQuantityEnabled = false }
                    }) {
                        Label("Nevermind", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            }
        }
    }

    private var locationButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .itemCategory }
            }) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(locationName.isEmpty ? .gray : (colorScheme == .dark ? .white : .black))
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(tintColor: locationName.isEmpty ? .gray : .white, interactive: !locationName.isEmpty)
            .disabled(locationName.isEmpty)
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemQuantity; locationName = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }

    private var categoryButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .reviewAndSave }
            }) {
                Label(categoryName.isEmpty ? "Skip" : "Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemLocation; categoryName = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }

    private var reviewButtons: some View {
        VStack(spacing: 16) {
            Button(action: { saveItem() }) {
                Label("Save Item", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemCategory }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }
    }
    
    private var animatedBackground: some View {
        Rectangle()
            .foregroundStyle(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            .blur(radius: 44)
            .ignoresSafeArea()
            .hueRotation(.degrees(animateGradient ? 45 : 0))
            .task {
                // From https://www.codespeedy.com/gradient-animation-in-swiftui/
                withAnimation(
                    .easeInOut(duration: 3)
                    .repeatForever())
                {
                    animateGradient.toggle()
                }
            }
    }
    
    private var progressBar: some View {
        VStack {
            ZStack {
                Text("Step \(creationProgress.rawValue + 1) of 6")
                    .font(.callout)
                    .foregroundStyle(.white)
                
                HStack {
                    Button(action: {
                        if creationProgress != .itemSymbol {
                            showDismissAlert = true
                        } else {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                }
            }.padding(.horizontal, 16)
            
            HStack(spacing: 8) {
                ForEach(0..<6) { index in
                    Capsule()
                        .fill(index <= creationProgress.rawValue ? .green : .white.opacity(0.4))
                        .frame(height: 8)
                }
            }.padding(.horizontal, 16)
        }.padding()
    }
    
    private var itemSymbol: some View {
        Group {
            if case .symbol(let symbol) = background, symbol.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Text("Give your item a look")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    Button(action: { showCamera = true }) {
                        Label("Capture Image", systemImage: "camera.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { showImagePicker = true }) {
                        Label("Pick from Photos", systemImage: "photo.fill.on.rectangle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { showSymbolPicker = true }) {
                        Label("Pick a Symbol", systemImage: "star.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
                VStack {
                    Text("Is this okay?")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                        ItemBackgroundView(background: background, symbolColor: symbolColor, mask: AnyView(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)))
                            .aspectRatio(1, contentMode: .fit)
                            .padding(16)
                        
                    if case .symbol = background {
                        ColorPicker("Symbol Color:", selection: $symbolColor, supportsOpacity: false)
                            .bold()
                            .frame(maxWidth: 200)
                            .padding(10)
                            .adaptiveGlassBackground(tintStrength: 0.5, tintColor: symbolColor)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isForward = true
                        withAnimation { creationProgress = .itemName }
                    }) {
                        Label("Looks Good!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = false
                        withAnimation { background = .symbol("") }
                    }) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            }
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerView(viewBehaviour: .tapToSelect, selectedSymbol: Binding(
                get: {
                    if case .symbol(let symbol) = background { return symbol } else { return "" }
                },
                set: { newSymbol in
                    isForward = true
                    withAnimation { background = .symbol(newSymbol) }
                }
            ))
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selection: Binding(
                get: {
                    nil
                },
                set: { newImage in
                    if let newImage {
                        selectedImage = newImage
                    }
                }
            ), sourceType: .photoLibrary)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(selection: Binding(
                get: {
                    nil
                },
                set: { newImage in
                    if let newImage {
                        selectedImage = newImage
                    }
                }
            ), sourceType: .camera)
        }
        .onChange(of: selectedImage) { _, newValue in
            if newValue != nil {
                // Show cropper after image is loaded
                showCropView = true
            }
        }
        .sheet(isPresented: $showCropView) {
            if let img = selectedImage {
                SwiftyCropView(
                    imageToCrop: img,
                    maskShape: .square,
                    configuration: swiftyCropConfiguration,
                    onComplete: { cropped in
                        if let cropped, let data = cropped.pngData() {
                            isForward = true
                            withAnimation { background = .image(data) }
                        }
                        showCropView = false
                        selectedImage = nil
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    private var itemName: some View {
        VStack {
            Spacer()
            
            Text("What do you want to call this item?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            
            TextField(
                "",
                text: Binding(
                    get: { name },
                    set: { newValue in
                        // Limit to 50 characters
                        withAnimation {
                            if newValue.count <= 50 {
                                name = newValue
                            } else {
                                name = String(newValue.prefix(50))
                            }
                        }
                    }
                ),
                prompt: Text("Item Name").foregroundStyle(.white.opacity(0.4))
            )
            .textFieldStyle(CleanTextFieldStyle())
            .font(.title3)
            .fontWeight(.medium)
            .fontDesign(.rounded)
            .padding(.horizontal)
            .autocapitalization(.words)
            .disableAutocorrection(true)
            .onSubmit {
                name = name.prefix(32).trimmingCharacters(in: .whitespacesAndNewlines)
                isForward = true
                withAnimation { creationProgress = .itemQuantity }
            }
            .onChange(of: name) { oldValue, newValue in
                if newValue.count >= 32 {
                    name = String(newValue.prefix(40))
                }
            }
            
            Spacer()
            
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .itemQuantity }
            }) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(name.isEmpty ? .gray : (colorScheme == .dark ? .white : .black))
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(tintColor: name.isEmpty ? .gray : .white, interactive: !name.isEmpty)
            .disabled(name.isEmpty)
            
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemSymbol; name = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }
    
    private var itemQuantity: some View {
        Group {
            if !isQuantityEnabled {
                VStack {
                    Spacer()
                    
                    Text("Do you have multiple of this item?")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    Button(action: {
                        isForward = true
                        withAnimation { isQuantityEnabled = true }
                    }) {
                        Label("Yes", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = true
                        withAnimation { isQuantityEnabled = false; creationProgress = .itemLocation }
                    }) {
                        Label("No", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = false
                        withAnimation { creationProgress = .itemName; quantity = 1 }
                    }) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
                VStack {
                    Spacer()
                    
                    Text("How many do you have?")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Stepper(value: $quantity, in: 1...100) {
                        HStack {
                            Group {
                                Text("Quantity: ")
                                TextField ("", value: $quantity, formatter: textFieldFormatter)
                                    .keyboardType(.numberPad)
                            }
                            .font(.title3)
                            .bold()
                            
                        }
                    }
                    .onSubmit { quantity = max(min(quantity, 100), 1) }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        isForward = true
                        withAnimation { creationProgress = .itemLocation }
                    }) {
                        Label("Next", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = false
                        withAnimation { isQuantityEnabled = false }
                    }) {
                        Label("Nevermind", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            }
        }
    }
    
    private var itemLocation: some View {
        VStack {
            Spacer()
            
            Text("Where is this item located?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 2) {
                HStack {
                    TextField(
                        "",
                        text: $locationName,
                        prompt: Text("Insert a location").foregroundStyle(.white.opacity(0.4))
                    )
                    .textFieldStyle(CleanTextFieldStyle())
                    .font(.title3)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .onSubmit {
                        locationName = locationName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                        isForward = true
                        withAnimation { creationProgress = .itemCategory }
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
                    
                    ColorPicker("", selection: $locationColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                        .padding(4)
                }
                
                filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $locationName, colorScheme: colorScheme)
            }.padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .itemCategory }
            }) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(locationName.isEmpty ? .gray : (colorScheme == .dark ? .white : .black))
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(tintColor: locationName.isEmpty ? .gray : .white, interactive: !locationName.isEmpty)
            .disabled(locationName.isEmpty)
            
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemQuantity; locationName = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }
    
    private var itemCategory: some View {
        VStack {
            Spacer()
            
            Text("What category does this item belong to?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack {
                TextField(
                    "",
                    text: Binding(
                        get: { categoryName },
                        set: { newValue in
                            // Limit to 30 characters
                            withAnimation {
                                if newValue.count <= 30 {
                                    categoryName = newValue
                                } else {
                                    categoryName = String(newValue.prefix(30))
                                }
                            }
                        }
                    ),
                    prompt: Text("Insert a category").foregroundStyle(.white.opacity(0.4))
                )
                .textFieldStyle(CleanTextFieldStyle())
                .font(.title3)
                .fontWeight(.medium)
                .fontDesign(.rounded)
                .padding(.horizontal)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .onSubmit {
                    categoryName = categoryName.prefix(40).trimmingCharacters(in: .whitespacesAndNewlines)
                    isForward = true
                    withAnimation { creationProgress = .reviewAndSave }
                }
                .onChange(of: categoryName) { oldValue, newValue in
                    if newValue.count >= 40 {
                        categoryName = String(newValue.prefix(40))
                    }
                }
                
                filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $categoryName, colorScheme: colorScheme)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: {
                isForward = true
                withAnimation { creationProgress = .reviewAndSave }
            }) {
                Label(categoryName.isEmpty ? "Skip" : "Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemLocation; categoryName = "" }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }
    
    private var reviewAndSave: some View {
        VStack {
            Text("Does this look good?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            itemCard(name: name, quantity: quantity, location: Location(name: locationName, color: locationColor), category: Category(name: categoryName), background: background, symbolColor: symbolColor, colorScheme: colorScheme, largeFont: true)
                .shadow(radius: 10)
                .aspectRatio(1, contentMode: .fit)
                .padding(16)
            
            Spacer()
            
            Button(action: { saveItem() }) {
                Label("Save Item", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
            
            Button(action: {
                isForward = false
                withAnimation { creationProgress = .itemCategory }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
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
        isPresented = false
    }
}

#Preview {
    @Previewable @State var isPresented: Bool = true
    
    InteractiveCreationView(isPresented: $isPresented)
}

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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = MotionManager()
    
    @Query(sort: \Location.name, order: .forward) var locations: [Location]
    @Query(sort: \Category.name, order: .forward) var categories: [Category]
    
    enum progress: Int {
        case itemSymbol
        case itemName
        case itemQuantity
        case itemLocation
        case itemCategory
        case reviewAndSave
    }
    
    @State var creationProgress: progress = .itemSymbol
    @State private var lastProgress: progress = .itemSymbol
    @State private var isForward: Bool = true
    @State private var animateGradient: Bool = false
    @State private var showCamera: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropView: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var showSymbolPicker: Bool = false
    
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
    
    var body: some View {
        ZStack {
            animatedBackground
            
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
        .onChange(of: creationProgress) { oldValue, newValue in
            lastProgress = oldValue
            isForward = newValue.rawValue > oldValue.rawValue
        }
    }
    
    private var animatedBackground : some View {
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
    
    private var progressBar : some View {
        VStack {
            Text("Step \(creationProgress.rawValue + 1) of 6")
                .font(.callout)
                .foregroundStyle(.white)
            
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
                        withAnimation { isQuantityEnabled = true; creationProgress = .itemLocation }
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
                    
                    ColorPicker("", selection: $locationColor)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            
            itemCard(name: name, quantity: quantity, location: Location(name: locationName, color: locationColor), category: Category(name: categoryName), background: background, colorScheme: colorScheme, largeFont: true)
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
        dismiss()
    }
}

#Preview {
    InteractiveCreationView()
}

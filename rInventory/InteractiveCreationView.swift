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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
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
    @State private var completedSteps: Set<progress> = []
    @State private var isForward: Bool = true
    @State private var animateGradient: Bool = false
    @State private var showCamera: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropView: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var showSymbolPicker: Bool = false
    @State private var showDismissAlert: Bool = false
    
    // Final Item Variables
    @State private var itemCardDisplacement: CGFloat = 0
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
    private var isVerticallyLimited: Bool {
        (UIDevice.current.userInterfaceIdiom == .phone && horizontalSizeClass == .regular) ||
        (UIDevice.current.userInterfaceIdiom == .pad && verticalSizeClass == .compact)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                animatedBackground
                
                VStack {
                    progressBar
                    if isVerticallyLimited {
                        HStack(alignment: .center) {
                            VStack {
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
                                .padding(16)
                                .foregroundStyle(.white)
                                .frame(maxWidth: 400, maxHeight: 800)
                                .transition(.asymmetric(
                                    insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                                ))
                            }
                            
                            VStack {
                                Spacer()
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
                                Spacer()
                            }
                            .frame(maxWidth: 300)
                            .padding(.trailing, 24)
                        }
                    } else {
                        VStack {
                            Group {
                                switch creationProgress {
                                case .itemSymbol:
                                    itemSymbol
                                    symbolButtons
                                case .itemName:
                                    itemName
                                    nameButtons
                                case .itemQuantity:
                                    itemQuantity
                                    quantityButtons
                                case .itemLocation:
                                    itemLocation
                                    locationButtons
                                case .itemCategory:
                                    itemCategory
                                    categoryButtons
                                case .reviewAndSave:
                                    reviewAndSave
                                    reviewButtons
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                            ))
                        }
                        .padding(16)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 400, maxHeight: 800)
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
                        if case .symbol(let symbol) = background, symbol.isEmpty, completedSteps.isEmpty {
                            isPresented = false
                        } else {
                            showDismissAlert = true
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
            }.padding(.horizontal, 16)
            
            let isStepTappable: (Int) -> Bool = { idx in
                guard idx > 0 else { return true }
                return (0..<idx).allSatisfy { completedSteps.contains(progress(rawValue: $0)!) }
            }
            
            HStack(spacing: 8) {
                ForEach(0..<6) { index in
                    let step = progress(rawValue: index)!
                    let isCompleted = completedSteps.contains(progress(rawValue: index)!)
                    let isCurrent = index == creationProgress.rawValue
                    let isReviewAndSave = step == .reviewAndSave
                    let reviewDisabled = completedSteps.count != 5
                    
                    Button(action: {
                        if isStepTappable(index) && !(isReviewAndSave && reviewDisabled) {
                            if step.rawValue > creationProgress.rawValue {
                                isForward = true
                            } else if step.rawValue < creationProgress.rawValue {
                                isForward = false
                            }
                            withAnimation { creationProgress = step }
                        }
                    }) {
                        Capsule()
                            .fill(
                                isCompleted ? .green :
                                (isCurrent ? .orange : (!isCompleted && isStepTappable(index) ? .orange : .white.opacity(0.4)))
                            )
                            .frame(height: 8)
                    }
                    .disabled(!isStepTappable(index) || (isReviewAndSave && reviewDisabled))
                }
            }.padding(.horizontal, 16)
        }.padding()
    }
    
    // MARK: - Item Symbol
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
                }.onAppear { completedSteps.remove(.itemSymbol) }
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
                        .padding(8)
                    if case .symbol = background {
                        ColorPicker("Symbol Color:", selection: $symbolColor, supportsOpacity: false)
                            .bold()
                            .frame(maxWidth: 200)
                            .padding(10)
                            .adaptiveGlassBackground(tintStrength: 0.5, tintColor: symbolColor)
                    }
                    Spacer()
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
            SwiftUICameraView(selectedImage: Binding(
                get: {
                    nil
                },
                set: { newImage in
                    if let newImage {
                        selectedImage = newImage
                    }
                }
            ))
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
    
    private var symbolButtons: some View {
        Group {
            if case .symbol(let symbol) = background, symbol.isEmpty {
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        Label("Camera", systemImage: "camera.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: { showImagePicker = true }) {
                        Label("Photo Library", systemImage: "photo.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    Button(action: { showSymbolPicker = true }) {
                        Label("Symbol", systemImage: "star.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
                VStack(spacing: 16) {
                    Button(action: {
                        isForward = true
                        withAnimation { creationProgress = .itemName; completedSteps.insert(.itemSymbol) }
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
        }.glassContain()
    }
    
    
    // MARK: - Item Name
    private var itemName: some View {
        VStack {
            Spacer()
            Text("What do you want to call this item?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack {
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
                    completedSteps.insert(.itemName)
                    withAnimation { creationProgress = .itemQuantity }
                }
                .onChange(of: name) { oldValue, newValue in
                    if newValue.count >= 32 {
                        name = String(newValue.prefix(40))
                    }
                    if name.isEmpty {
                        completedSteps.remove(.itemName)
                    }
                }
                
                Button(action: { name = "" }, label: {
                    Label("Clear Text Field", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white)
                })
            }
            Spacer()
        }
    }
    
    private var nameButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                completedSteps.insert(.itemName)
                hideKeyboard()
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
                hideKeyboard()
                withAnimation { creationProgress = .itemSymbol }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }.glassContain()
    }
    
    // MARK: - Item Quantity
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
                    .padding()
                    .onSubmit {
                        quantity = max(min(quantity, 100), 1)
                        isForward = true
                        completedSteps.insert(.itemQuantity)
                        withAnimation { creationProgress = .itemLocation }
                    }
                    
                    Spacer()
                }
            }
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
                        completedSteps.insert(.itemQuantity)
                        withAnimation { isQuantityEnabled = false; creationProgress = .itemLocation }
                    }) {
                        Label("No", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = false
                        withAnimation { creationProgress = .itemName }
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
                        hideKeyboard()
                        withAnimation { creationProgress = .itemLocation; completedSteps.insert(.itemQuantity) }
                    }) {
                        Label("Next", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: {
                        isForward = false
                        hideKeyboard()
                        withAnimation { isQuantityEnabled = false }
                    }) {
                        Label("Nevermind", systemImage: "xmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                }
            }
        }.glassContain()
    }
    
    // MARK: - Item Location
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
                        completedSteps.insert(.itemLocation)
                        withAnimation { creationProgress = .itemCategory }
                    }
                    
                    ColorPicker("", selection: $locationColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 24, height: 24)
                        .padding(4)
                    
                    Button(action: { locationName = "" }, label: {
                        Label("Clear Text Field", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white)
                    })
                }
                
                filteredSuggestionsPicker(items: locations, keyPath: \Location.name, filter: $locationName, colorScheme: colorScheme)
            }.padding(.horizontal)
            
            Spacer()
        }
        .onChange(of: locationName) { oldValue, newValue in
            if newValue.count >= 40 {
                locationName = String(newValue.prefix(40))
            }
            if locationName.isEmpty { completedSteps.remove(.itemLocation) }
            if let found = locations.first(where: { $0.name == newValue }) {
                locationColor = found.color
            } else {
                locationColor = .white
            }
        }
    }
    
    private var locationButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                completedSteps.insert(.itemLocation)
                hideKeyboard()
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
                hideKeyboard()
                withAnimation { creationProgress = .itemQuantity }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }.glassContain()
    }
    
    // MARK: - Item Category
    private var itemCategory: some View {
        VStack {
            Spacer()
            Text("What category does this item belong to?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack {
                HStack {
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
                    
                    Button(action: { categoryName = "" }, label: {
                        Label("Clear Text Field", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white)
                    })
                }
                filteredSuggestionsPicker(items: categories, keyPath: \Category.name, filter: $categoryName, colorScheme: colorScheme)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .onChange(of: categoryName) { oldValue, newValue in
            if newValue.count >= 40 {
                categoryName = String(newValue.prefix(40))
            }
            if categoryName.isEmpty { completedSteps.remove(.itemCategory) }
        }
    }
    
    private var categoryButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                isForward = true
                completedSteps.insert(.itemCategory)
                hideKeyboard()
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
                hideKeyboard()
                withAnimation { creationProgress = .itemLocation }
            }) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }.glassContain()
    }
    
    // MARK: - Review and Save
    private var reviewAndSave: some View {
        VStack {
            Text("Does this look good?")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            itemCard(name: name, quantity: isQuantityEnabled ? quantity : 0, location: Location(name: locationName, color: locationColor), category: Category(name: categoryName), background: background, symbolColor: symbolColor, colorScheme: colorScheme, largeFont: true)
                .offset(y: itemCardDisplacement)
                .shadow(radius: 10)
                .aspectRatio(1, contentMode: .fit)
                .padding(16)
            Spacer()
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
        }.glassContain()
    }
    
    // MARK: - Functions
    private func saveItem() {
        withAnimation(.easeInOut(duration: 0.5)) {
            itemCardDisplacement = -768
            completedSteps.insert(.reviewAndSave)
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
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPresented = false
        }
    }
}

extension View {
    func glassContain() -> some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    self
                }
            } else {
                self
            }
        }
    }
    
#if canImport(UIKit)
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
#endif
}


#Preview {
    @Previewable @State var isPresented: Bool = true
    
    InteractiveCreationView(isPresented: $isPresented)
}


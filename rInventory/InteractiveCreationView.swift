//
//  InteractiveCreationView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/17/25.
//

import SwiftUI
import SwiftyCrop
import Playgrounds

struct InteractiveCreationView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showCamera: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var showCropView: Bool = false
    @State private var selectedImage: UIImage? = nil
    
    @State private var showSymbolPicker: Bool = false
    
    enum progress: Int {
        case itemSymbol
        case itemName
        case itemQuantity
        case itemLocation
        case itemCategory
        case reviewAndSave
    }
    
    // Final Item Variables
    @State var creationProgress: progress = .itemSymbol
    @State private var background: ItemCardBackground? = nil
    @State private var symbolColor: Color = .white
    @State private var name: String = ""
    @State private var isQuantityEnabled: Bool = false
    @State private var quantity: Int = 1
    @State private var location: Location? = nil
    @State private var category: Category? = nil
    
    @State private var animateGradient: Bool = false
    /// Dynamically computes gradient colors based on colorScheme.
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
                        Text("Item Location View")
                    case .itemCategory:
                        Text("Item Category View")
                    case .reviewAndSave:
                        Text("Review and Save View")
                    }
                }
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .transition(.push(from: .trailing))
                .frame(maxWidth: 400, maxHeight: 800)
                .padding(16)
            }
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
                .foregroundStyle(colorScheme == .dark ? .black : .white)
            
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
            if let bg = background {
                VStack {
                    Text("Is this okay?")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    ItemBackgroundView(background: bg, symbolColor: symbolColor, mask: AnyView(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)))
                        .aspectRatio(1, contentMode: .fit)
                        .padding(16)
                    
                    Spacer()
                    
                    Button(action: { withAnimation{ creationProgress = .itemName }}) {
                        Label("Looks Good!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { withAnimation { background = nil }}) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
            } else {
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
            }
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerView(viewBehaviour: .tapToSelect, selectedSymbol: Binding(
                get: {
                    if case .symbol(let symbol) = background { return symbol } else { return "" }
                },
                set: { newSymbol in
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
                text: $name,
                prompt: Text("Item Name").foregroundStyle(.white.opacity(0.4))
            )
                .textFieldStyle(CleanTextFieldStyle())
                .font(.title3)
                .fontWeight(.medium)
                .fontDesign(.rounded)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: { withAnimation{ creationProgress = .itemQuantity }}) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
            
            Button(action: { withAnimation { creationProgress = .itemSymbol; name = "" }}) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
    }
    
    private var itemQuantity: some View {
        VStack {
            if !isQuantityEnabled {
                Spacer()
                
                Text("Do you have multiple of this item?")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                Button(action: { withAnimation{ isQuantityEnabled = true }}) {
                    Label("Yes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding()
                        .frame(maxWidth: .infinity)
                }.adaptiveGlassButton()
                
                Button(action: { withAnimation{ isQuantityEnabled = false; creationProgress = .itemLocation }}) {
                    Label("No", systemImage: "xmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding()
                        .frame(maxWidth: .infinity)
                }.adaptiveGlassButton()
            } else {
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
                .onSubmit { max(min(quantity, 100), 1) }
                .padding()
                
                Spacer()
                
                Button(action: { withAnimation{ creationProgress = .itemLocation }}) {
                    Label("Next", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding()
                        .frame(maxWidth: .infinity)
                }.adaptiveGlassButton()
                
                Button(action: { withAnimation{ isQuantityEnabled = false }}) {
                    Label("Nevermind", systemImage: "xmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding()
                        .frame(maxWidth: .infinity)
                }.adaptiveGlassButton()
            }
        }
    }
}

#Preview {
    InteractiveCreationView()
}

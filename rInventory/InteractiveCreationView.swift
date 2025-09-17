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
    
    enum progress {
        case itemSymbol
        case itemName
        case itemQuantity
        case itemLocation
        case itemCategory
        case reviewAndSave
    }
    
    // Final Item Variables
    @State private var creationProgress: progress = .itemSymbol
    @State private var background: ItemCardBackground? = nil
    @State private var symbolColor: Color = .white
    @State private var name: String = ""
    @State private var isQuantityEnabled: Bool = false
    @State private var quantity: String = "1"
    @State private var location: Location? = nil
    @State private var category: Category? = nil
    
    @State private var animateGradient: Bool = false
    /// Dynamically computes gradient colors based on colorScheme.
    private var gradientColors: [Color] {
        colorScheme == .light ? [.accentLight, .accentDark] : [.accentDark, .accentLight]
    }
    
    var body: some View {
        ZStack {
            animatedBackground
            
            switch creationProgress {
            case .itemSymbol:
                itemSymbol
            case .itemName:
                itemName
            case .itemQuantity:
                Text("Item Quantity View")
            case .itemLocation:
                Text("Item Location View")
            case .itemCategory:
                Text("Item Category View")
            case .reviewAndSave:
                Text("Review and Save View")
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
    
    private var itemSymbol: some View {
        ZStack {
            if let bg = background {
                VStack {
                    Text("Is this okay?")
                        .font(.title3)
                        .bold()
                    
                    Spacer()
                    
                    ItemBackgroundView(background: bg, symbolColor: symbolColor, mask: AnyView(RoundedRectangle(cornerRadius: ItemCardConstants.cornerRadius)))
                        .aspectRatio(1, contentMode: .fill)
                        .padding(16)
                    
                    Spacer()
                    
                    Button(action: { withAnimation{ creationProgress = .itemName }}) {
                        Label("Looks Good!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { withAnimation { background = nil }}) {
                        Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .aspectRatio(0.75, contentMode: .fit)
                .frame(maxHeight: 600)
                .padding(16)
            } else {
                VStack(spacing: 16) {
                    Text("Capture an image or pick a symbol")
                        .font(.title3)
                        .bold()
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    Button(action: { showCamera = true }) {
                        Label("Capture Image", systemImage: "camera.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { showImagePicker = true }) {
                        Label("Pick from Photos", systemImage: "photo.fill.on.rectangle.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                    
                    Button(action: { showSymbolPicker = true }) {
                        Label("Pick a Symbol", systemImage: "star.fill")
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }.adaptiveGlassButton()
                }
                .frame(maxWidth: 400, maxHeight: 600)
                .padding(16)
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
            Text("What do you want to call this item?")
                .font(.title3)
                .bold()
                .multilineTextAlignment(.center)
            
            Spacer()
            
            TextField("Item Name", text: $name)
                .textFieldStyle(CleanTextFieldStyle())
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: { withAnimation{ creationProgress = .itemQuantity }}) {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
            
            Button(action: { withAnimation { creationProgress = .itemSymbol; name = "" }}) {
                Label("Go Back", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
            }.adaptiveGlassButton()
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .frame(maxWidth: 400, maxHeight: 600)
        .padding(16)
    }
}

#Preview {
    InteractiveCreationView()
}

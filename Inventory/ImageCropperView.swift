//
//  ImageCropperView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/5/25.
//

import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var cropRect: CGRect = .zero
    @State private var startLocation: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .path(in: cropFrame(in: geometry.size))
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if startLocation == nil {
                                    startLocation = value.startLocation
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { _ in
                                cropRect = cropRect.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
                                dragOffset = .zero
                                startLocation = nil
                            }
                    )
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("Crop") {
                            if let cropped = cropImage(in: geometry.size) {
                                onCrop(cropped)
                                dismiss()
                            }
                        }
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .onAppear {
                // Center square crop
                let side = min(geometry.size.width, geometry.size.height) * 0.8
                let origin = CGPoint(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2)
                cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
            }
        }
    }
    
    private func cropFrame(in size: CGSize) -> CGRect {
        cropRect.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
    }
    
    private func cropImage(in size: CGSize) -> UIImage? {
        let displayedSize = CGSize(width: size.width, height: size.width)
        let scale = image.size.width / displayedSize.width
        let crop = cropFrame(in: size)
        let cropRectInImage = CGRect(
            x: crop.origin.x * scale,
            y: crop.origin.y * scale,
            width: crop.size.width * scale,
            height: crop.size.height * scale
        )
        guard let cgImage = image.cgImage?.cropping(to: cropRectInImage) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

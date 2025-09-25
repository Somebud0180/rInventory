import SwiftUI
import AVFoundation

// Focus square view - shows where the camera is focused
struct FocusSquare: View {
    var point: CGPoint
    
    var body: some View {
        GeometryReader { geometry in
            let size: CGFloat = 80
            let x = point.x * geometry.size.width
            let y = point.y * geometry.size.height
            
            Rectangle()
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: size, height: size)
                .position(x: x, y: y)
        }
        .allowsHitTesting(false)
    }
}

// Exposure slider view - appears when adjusting exposure
struct ExposureSlider: View {
    var point: CGPoint
    @Binding var value: Float
    var onChange: (Float) -> Void
    
    // Constants for slider
    private let minValue: Float = -2.0
    private let maxValue: Float = 2.0
    private let step: Float = 0.1
    private let sliderHeight: CGFloat = 140
    private let trackWidth: CGFloat = 2
    private let thumbSize: CGFloat = 20
    private let maskSize: CGFloat = 24
    
    var body: some View {
        // Vertical slider with custom masking
        GeometryReader { geometry in
            let height = geometry.size.height
            let yOffset = yOffset(for: value, height: height)
            
            ZStack {
                // Masked vertical track
                trackWithThumbMask(yOffset: yOffset, height: height)
                
                // Thumb (sun symbol)
                Image(systemName: "sun.max.fill")
                    .resizable()
                    .foregroundStyle(Color.yellow)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(y: yOffset)
                    .animation(.easeInOut(duration: 0.1), value: value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: 30, height: sliderHeight)
            .padding(6)
            .cornerRadius(9)
        }
        .allowsHitTesting(false)
    }
    
    // Helper: vertical offset for sun thumb
    private func yOffset(for value: Float, height: CGFloat) -> CGFloat {
        let clamped = min(max(value, minValue), maxValue)
        let percent = CGFloat((clamped - minValue) / (maxValue - minValue))
        return (1 - percent) * (height - thumbSize) - (height / 2 - thumbSize / 2)
    }
    
    // Masked track: cuts rectangle behind thumb
    private func trackWithThumbMask(yOffset: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // The yellow track
            RoundedRectangle(cornerRadius: trackWidth/2)
                .fill(Color.yellow.opacity(0.7))
                .frame(width: trackWidth)
                .frame(maxHeight: .infinity)
                .mask(
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: (height/2 + yOffset) - maskSize/2)
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: maskSize)
                            .opacity(0) // cut out where the thumb goes
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: (height/2 - yOffset) - maskSize/2)
                    }
                )
        }
    }
}

// Combined focus and exposure view - uses HStack for reliable positioning
struct FocusExposureView: View {
    var point: CGPoint
    @Binding var exposureValue: Float
    var onExposureChange: (Float) -> Void
    var showExposure: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let x = point.x * geometry.size.width
            let y = point.y * geometry.size.height
            
            HStack(alignment: .center, spacing: 15) {
                FocusSquare(point: .zero)
                    .frame(width: 60, height: 60)
                
                if showExposure {
                    ExposureSlider(
                        point: .zero,
                        value: $exposureValue,
                        onChange: onExposureChange
                    )
                    .frame(width: 30, height: 140)
                }
            }
            .position(x: x, y: y)
        }
        .allowsHitTesting(false)
    }
}

// Preview provider for camera focus components
struct CameraFocusComponents_Previews: PreviewProvider {
    @State static var exampleValue: Float = 0.5
    
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Preview with combined view
            FocusExposureView(
                point: CGPoint(x: 0.5, y: 0.5),
                exposureValue: $exampleValue,
                onExposureChange: { _ in },
                showExposure: true
            )
        }
    }
}

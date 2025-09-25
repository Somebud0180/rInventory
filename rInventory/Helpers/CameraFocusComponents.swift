import SwiftUI
import AVFoundation
import Combine

// Focus square view - shows where the camera is focused
struct FocusSquare: View {
    var body: some View {
        let size: CGFloat = 80
        
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: size, height: size)
    }
}

// Exposure slider view - appears when adjusting exposure
struct ExposureSlider: View {
    @Binding var value: Float
    @Binding var isInactive: Bool
    
    // Constants for slider
    private let minValue: Float = -2.0
    private let maxValue: Float = 2.0
    private let step: Float = 0.1
    private let sliderHeight: CGFloat = 120
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
                if !isInactive {
                    trackWithThumbMask(yOffset: yOffset, height: height)
                }
                
                // Thumb (sun symbol)
                Image(systemName: "sun.max.fill")
                    .resizable()
                    .foregroundStyle(Color.yellow)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(y: yOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(6)
            .cornerRadius(9)
        }
        .frame(width: 30, height: sliderHeight)
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
                            .frame(height: max(0, (height/2 + yOffset) - maskSize/2))
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: maskSize)
                            .opacity(0)
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height:  max(0, (height/2 - yOffset) - maskSize/2))
                    }
                )
        }
    }
}

// Combined focus and exposure view - uses HStack for reliable positioning
struct FocusExposureView: View {
    @Binding var exposureValue: Float
    var isFrontCamera: Bool
    var point: CGPoint
    
    @State private var opacity: Double = 1.0
    @State private var isInactive: Bool = true
    @State private var inactivityTimer: AnyCancellable?
    
    var body: some View {
        GeometryReader { geometry in
            let x = point.x * geometry.size.width
            let y = point.y * geometry.size.height
            
            HStack(alignment: .center, spacing: 4) {
                // Center the focus square vertically
                FocusSquare()
                    .opacity(opacity)
                    .onTapGesture {
                        resetInactivityTimer() // Reactivate on tap
                    }
                
                ExposureSlider(value: $exposureValue, isInactive: $isInactive)
                .opacity(opacity)
            }
            .position(x: x, y: y)
            .onChange(of: exposureValue) {
                resetInactivityTimer()
            }
            .onAppear {
                resetInactivityTimer()
            }
        }
    }
    
    private func resetInactivityTimer() {
        inactivityTimer?.cancel()
        opacity = 1.0
        isInactive = false
        
        inactivityTimer = Just(()).delay(for: .seconds(3), scheduler: RunLoop.main).sink { _ in
            withAnimation {
                opacity = 0.5
                isInactive = true
            }
        }
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
                exposureValue: $exampleValue,
                isFrontCamera: false,
                point: CGPoint(x: 0.5, y: 0.5)
            )
        }
    }
}

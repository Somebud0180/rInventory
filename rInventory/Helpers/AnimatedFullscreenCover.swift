//
//  AnimatedFullscreenCover.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/19/25.
//

import SwiftUI

struct AnimatedFullscreenCover<OverlayContent: View>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPresented: Bool
    let overlayContent: () -> OverlayContent
    
    // This is the correct signature for a ViewModifier's body method
    func body(content: Content) -> some View {
        let colorBackground = colorScheme == .dark ? Color.black : Color.white
        ZStack {
            content
                .disabled(isPresented)
            
            if isPresented {
                colorBackground
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            isPresented = false
                        }
                    }
                
                overlayContent()
                    .transition(.blurReplace)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isPresented)
    }
}

extension View {
    func animatedFullscreenCover<OverlayContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> OverlayContent
    ) -> some View {
        self.modifier(AnimatedFullscreenCover(isPresented: isPresented, overlayContent: content))
    }
}

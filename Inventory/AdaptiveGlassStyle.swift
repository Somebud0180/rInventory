//
//  AdaptiveGlassStyle.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI

// Liquid Glass / Tinted (Edit) Button Modifier
struct AdaptiveGlassEditButtonModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isEditing: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular
                    .tint(isEditing ? Color.blue.opacity(0.9) : colorScheme == .dark ? .gray.opacity(0.9) : .white.opacity(0.9))
                    .interactive()
                )
        } else {
            content
                .background(isEditing ? Color.blue.opacity(0.9) : colorScheme == .dark ? .gray.opacity(0.9) : .white.opacity(0.9))
        }
    }
}

// Liquid Glass / Tinted Button Background
struct AdaptiveGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let tint: Color?
    
    func body(content: Content) -> some View {
        let tintColor = tint ?? (colorScheme == .dark ? .gray.opacity(0.9) : .white.opacity(0.9))
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular
                    .tint(tintColor)
                    .interactive()
                )
        } else {
            content
                .background(tintColor)
        }
    }
}


// Liquid Glass / Ultra Thin Capsule Background Style
struct AdaptiveGlassBackground<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let tintStrength: CGFloat
    let shape: S
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(colorScheme == .dark ? .gray.opacity(0.2) : .gray.opacity(tintStrength)),
                    in: shape)
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: shape)
        }
    }
}

extension View {
    func adaptiveGlassEditButton(_ isEditing: Bool = false) -> some View {
        self.modifier(AdaptiveGlassEditButtonModifier(isEditing: isEditing))
    }
    
    func adaptiveGlassButton(tint: Color? = nil) -> some View {
        self.modifier(AdaptiveGlassButtonModifier(tint: tint))
    }
    
    func adaptiveGlassBackground<S: Shape>(tintStrength: CGFloat = 0.9, shape: S = Capsule()) -> some View {
        self.modifier(AdaptiveGlassBackground(tintStrength: tintStrength, shape: shape))
    }
}

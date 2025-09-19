//
//  AdaptiveGlassStyle.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/4/25.
//
//  This file contains adaptive glass style modifiers for buttons and backgrounds. Made to enable the new Liquid Glass design while maintaining compatibility with earlier iOS versions.

import SwiftUI

// Liquid Glass / Tinted (Edit) Button Modifier
struct AdaptiveGlassEditButtonModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isEditing: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                    .tint(isEditing ? .accentLight.opacity(0.9) : colorScheme == .dark ? .gray.opacity(0.9) : .white.opacity(0.9))
                    .interactive()
                )
        } else {
            content
                .background(isEditing ? .accentLight.opacity(0.9) : colorScheme == .dark ? .gray.opacity(0.9) : .white.opacity(0.9), in: Capsule())
        }
    }
}

// Liquid Glass / Tinted Button Background
struct AdaptiveGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let tintStrength: CGFloat
    let tint: Color
    let interactive: Bool
    let simplified: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *), !simplified {
            let tintColor = colorScheme == .dark ? tint.opacity(0.2) : tint.opacity(tintStrength)
            if tintStrength == 0.0 {
                content
                    .glassEffect(
                        .regular
                        .interactive(interactive)
                    )
            } else {
                content
                    .glassEffect(
                        .regular
                        .tint(tintColor)
                        .interactive(interactive)
                    )
            }
        } else {
            let tintColor = colorScheme == .dark ? tint.opacity(0.2) : tint.opacity(max(tintStrength, 0.2))
            content
                .background(tintColor, in: Capsule())
        }
    }
}


// Liquid Glass / Ultra Thin Capsule Background Style
struct AdaptiveGlassBackground<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let tintStrength: CGFloat
    let tint: Color
    let simplified: Bool
    let shape: S
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *), !simplified {
            let tintColor = colorScheme == .dark ? tint.opacity(0.4) : tint.opacity(tintStrength)
            content
                .glassEffect(
                    .regular
                    .tint(tintColor),
                    in: shape)
        } else {
            let tintColor = colorScheme == .dark ? tint.opacity(0.8) : tint.opacity(tintStrength)
            content
                .background(tintColor, in: shape)
        }
    }
}

extension View {
    func adaptiveGlassEditButton(_ isEditing: Bool = false) -> some View {
        self.modifier(AdaptiveGlassEditButtonModifier(isEditing: isEditing))
    }
    
    func adaptiveGlassButton(tintStrength: CGFloat = 0.8, tintColor: Color = Color.white, interactive: Bool = true, simplified: Bool = false) -> some View {
        self.modifier(AdaptiveGlassButtonModifier(tintStrength: tintStrength, tint: tintColor, interactive: interactive, simplified: simplified))
    }
    
    func adaptiveGlassBackground<S: Shape>(tintStrength: CGFloat = 0.8, tintColor: Color = Color.gray, simplified: Bool = false, shape: S = Capsule()) -> some View {
        self.modifier(AdaptiveGlassBackground(tintStrength: tintStrength, tint: tintColor, simplified: simplified, shape: shape))
    }
}


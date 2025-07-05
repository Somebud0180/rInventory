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
struct AdaptiveGlassBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular
                    .tint(colorScheme == .dark ? .gray.opacity(0.2) : .white.opacity(0.9))
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
            
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
    
    func adaptiveGlassBackground() -> some View {
        self.modifier(AdaptiveGlassBackground())
    }
}

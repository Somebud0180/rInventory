//
//  AdaptiveGlassStyle.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI

struct AdaptiveGlassButtonModifier: ViewModifier {
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

extension View {
    func adaptiveGlassButton(_ isEditing: Bool = false) -> some View {
        self.modifier(AdaptiveGlassButtonModifier(isEditing: isEditing))
    }
}

struct AdaptiveGlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isEditing: Bool
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

extension View {
    func adaptiveGlass(_ isEditing: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(AdaptiveGlassModifier(isEditing: isEditing, tint: tint))
    }
}

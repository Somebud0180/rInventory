//
//  AdaptiveGlassStyle.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/4/25.
//

import SwiftUI

struct AdaptiveGlassButtonModifier: ViewModifier {
    let isEditing: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular
                    .tint(isEditing ? Color.blue.opacity(0.9) : .white.opacity(0.9))
                    .interactive()
                )
        } else {
            content
                .background(isEditing ? Color.blue.opacity(0.9) : Color.white.opacity(0.9))
        }
    }
}

extension View {
    func adaptiveGlassButton(_ isEditing: Bool = false) -> some View {
        self.modifier(AdaptiveGlassButtonModifier(isEditing: isEditing))
    }
}

struct AdaptiveGlassModifier: ViewModifier {
    let isEditing: Bool
    let tint: Color
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular
                    .tint(tint)
                    .interactive()
                )
        } else {
            content
                .background(tint)
        }
    }
}

extension View {
    func adaptiveGlass(_ isEditing: Bool = false, tint: Color = .white) -> some View {
        self.modifier(AdaptiveGlassModifier(isEditing: isEditing, tint: tint))
    }
}

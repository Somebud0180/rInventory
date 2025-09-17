//
//  TextFieldStyles.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/17/25.
//

import SwiftUI

// From https://nicoladefilippo.com/shape-stroke-and-dash-in-swiftui/
struct Line: Shape {
    var y2: CGFloat = 0.0
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: y2))
        return path
    }
}

struct CleanTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .background(Color.clear)
                .overlay(
                    VStack {
                        Spacer()
                        
                        Line()
                            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                            .foregroundColor(.accentColor)
                            .frame(height: 3)
                    }
                )
        }
    }
}

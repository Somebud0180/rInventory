import SwiftUI

struct SmoothColorSchemeView<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showOverlay = false
    @State private var lastColorScheme: ColorScheme = .light
    let content: () -> Content

    var body: some View {
        ZStack {
            content()
            if showOverlay {
                Color(colorScheme == .dark ? .black : .white)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: showOverlay)
            }
        }
        .onChange(of: colorScheme) { newScheme in
            showOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showOverlay = false
                lastColorScheme = newScheme
            }
        }
    }
}

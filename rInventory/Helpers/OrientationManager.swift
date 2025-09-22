//
//  OrientationManager.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/23/25.
//

import SwiftUI

// MARK: - Orientation Lock View Modifier
struct DeviceOrientationViewModifier: ViewModifier {
    let orientation: UIInterfaceOrientationMask
    
    func body(content: Content) -> some View {
        content
            .onAppear() {
                OrientationManager.lockOrientation(orientation)
            }
            .onDisappear() {
                OrientationManager.unlockOrientation()
            }
    }
}

// MARK: - View Extension for Orientation Lock
extension View {
    func lockDeviceOrientation(_ orientation: UIInterfaceOrientationMask) -> some View {
        self.modifier(DeviceOrientationViewModifier(orientation: orientation))
    }
}

// MARK: - Orientation Manager
class OrientationManager {
    // Lock to specific orientation
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
        
        // Force the orientation change by setting the device orientation
        let orientationValue: Int
        
        switch orientation {
        case .portrait:
            orientationValue = UIInterfaceOrientation.portrait.rawValue
        case .landscapeLeft:
            orientationValue = UIInterfaceOrientation.landscapeLeft.rawValue
        case .landscapeRight:
            orientationValue = UIInterfaceOrientation.landscapeRight.rawValue
        case .portraitUpsideDown:
            orientationValue = UIInterfaceOrientation.portraitUpsideDown.rawValue
        default:
            orientationValue = UIInterfaceOrientation.portrait.rawValue
        }
        
        UIDevice.current.setValue(orientationValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
    
    // Unlock orientation
    static func unlockOrientation() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
        }
    }
}

//
//  CameraView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 8/2/25.
//

import SwiftUI
import MijickCamera

struct CustomCameraScreen: MCameraScreen {
    @ObservedObject var cameraManager: CameraManager
    let namespace: Namespace.ID
    let closeMCameraAction: () -> ()
    
    var body: some View {
        DefaultCameraScreen(cameraManager: cameraManager, namespace: namespace, closeMCameraAction: closeMCameraAction)
            .cameraOutputSwitchAllowed(false)
    }
}

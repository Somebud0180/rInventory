//
//  MotionManager.swift
//  rInventory
//
//  Created by Ethan John Lagera on 9/19/25.
//
//  MotionManager to track device orientation using CoreMotion
//  Also includes a ViewModifier for 3D card effect based on device tilt


import CoreMotion
import SwiftUI
import Combine

class MotionManager: ObservableObject {
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    private var motionManager = CMMotionManager()

    init() {
        motionManager.deviceMotionUpdateInterval = 1/60
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            self?.pitch = motion.attitude.pitch
            self?.roll = motion.attitude.roll
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct Card3DEffect: ViewModifier {
    let pitch: Double
    let roll: Double
    let perspective: CGFloat
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(pitch * -5), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(roll * 5), axis: (x: 0, y: 1, z: 0))
            .projectionEffect(
                .init(CATransform3D.MakePerspective(distance: 1.0/perspective))
            )
    }
}

extension CATransform3D {
    static func MakePerspective(distance: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m34 = distance * -1
        return t
    }
}

extension View {
    func card3DEffect(pitch: Double, roll: Double, perspective: CGFloat = 0.5) -> some View {
        self.modifier(Card3DEffect(pitch: pitch, roll: roll, perspective: perspective))
    }
}

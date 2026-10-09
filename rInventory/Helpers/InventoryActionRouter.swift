import Combine
import UIKit

@MainActor
final class InventoryActionRouter: ObservableObject {
    static let shared = InventoryActionRouter()
    static let addItemShortcutType = "com.lagera.Inventory.addItem"
    @Published var newItemRequested = false

    func requestNewItem() { newItemRequested = true }

    @discardableResult
    func handle(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard shortcut.type == Self.addItemShortcutType else { return false }
        requestNewItem()
        return true
    }
}

final class InventoryAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Capture cold-launch actions before SwiftUI creates its root view.
        if let shortcut = options.shortcutItem {
            InventoryActionRouter.shared.handle(shortcut)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = InventorySceneDelegate.self
        return configuration
    }
}

final class InventorySceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(InventoryActionRouter.shared.handle(shortcutItem))
    }
}

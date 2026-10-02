import Foundation
import SwiftData
import Combine

/// Device-local presentation preferences; never mutate synced inventory entities.
@MainActor
final class WatchVisibilityPreferences: ObservableObject {
    static let shared = WatchVisibilityPreferences()
    @Published private(set) var revision = 0
    private(set) var accountKey = "offline"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ zone: String, _ id: UUID) -> String { "watch-visibility-\(accountKey)-\(zone)-\(id)" }
    func visible(zone: String, id: UUID, fallback: Bool) -> Bool {
        defaults.object(forKey: key(zone, id)) as? Bool ?? fallback
    }
    func toggle(zone: String, id: UUID, fallback: Bool) {
        defaults.set(!visible(zone: zone, id: id, fallback: fallback), forKey: key(zone, id))
        revision += 1
    }
    func activate(accountKey: String, context: ModelContext) {
        self.accountKey = accountKey
        let migrationKey = "watch-visibility-migrated-\(accountKey)"
        if !defaults.bool(forKey: migrationKey) {
            // Only seed existing cached entities; newly downloaded entities use the cloud value as default.
            for category in (try? context.fetch(FetchDescriptor<Category>())) ?? [] {
                defaults.set(category.displayInRow, forKey: key(SyncPersistence.categoriesZone, category.id))
            }
            for location in (try? context.fetch(FetchDescriptor<Location>())) ?? [] {
                defaults.set(location.displayInRow, forKey: key(SyncPersistence.locationsZone, location.id))
            }
            defaults.set(true, forKey: migrationKey)
        }
        revision += 1
    }
}

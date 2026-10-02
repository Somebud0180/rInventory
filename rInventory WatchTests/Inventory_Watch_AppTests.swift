import Testing
import Foundation
import SwiftData
import CloudKit
@testable import rInventory_Watch

@MainActor
private final class WatchTestTransport: InventorySyncTransport {
    weak var delegate: CloudKitSyncEngine?
    var uploads = 0
    var fetches = 0
    func start(delegate: CloudKitSyncEngine, inventoryState: CKSyncEngine.State.Serialization?, markerState: CKSyncEngine.State.Serialization?) { self.delegate = delegate }
    func ensureZones() async throws { uploads += 1 }
    func fetchMarkers() async throws {}
    func fetchInventory() async throws {
        fetches += 1
        let record = CKRecord(recordType: "CD_Item", recordID: CKRecord.ID(recordName: "8A3A85E1-9CA5-40D0-AF11-C29ED841D09F", zoneID: CKRecordZone.ID(zoneName: "InventoryItems")))
        record["CD_name"] = "Watch item"; record["CD_quantity"] = 1
        try await delegate?.ingest(records: [record])
    }
    func sendMarkers() async throws { uploads += 1 }
    func sendInventory() async throws { uploads += 1 }
    func queueInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { uploads += changes.count }
    func queueMarkers(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { uploads += changes.count }
    func removeInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) {}
    func stop() async {}
}

@Suite(.serialized)
@MainActor
struct Inventory_WatchTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: SyncPersistence.schema, configurations: [ModelConfiguration(schema: SyncPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    @Test func downloadOnlyRefreshNeverUploadsInventory() async throws {
        let container = try store(); let transport = WatchTestTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, mode: .downloadOnly, transport: transport)
        try engine.start()
        async let first: Void = engine.manualSync()
        async let second: Void = engine.manualSync()
        _ = await (first, second)
        #expect(transport.uploads == 0)
        #expect(transport.fetches == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Item>()) == 1)
    }
    @Test func visibilityDoesNotModifyInventory() throws {
        let container = try store(); let context = container.mainContext
        let location = Location(name: "Shelf"); context.insert(location); try context.save()
        let suite = "watch-preference-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WatchVisibilityPreferences(defaults: defaults)
        preferences.activate(accountKey: "A", context: context)
        preferences.toggle(zone: SyncPersistence.locationsZone, id: location.id, fallback: true)
        #expect(location.displayInRow && !context.hasChanges)
        let restored = WatchVisibilityPreferences(defaults: defaults)
        restored.activate(accountKey: "A", context: context)
        #expect(!restored.visible(zone: SyncPersistence.locationsZone, id: location.id, fallback: true))
    }
}

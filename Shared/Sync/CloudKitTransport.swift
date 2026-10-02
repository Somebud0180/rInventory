import CloudKit
import Foundation

/// Injectable boundary for network scheduling; reconciliation remains testable without iCloud.
@MainActor
protocol InventorySyncTransport: AnyObject {
    func start(delegate: CloudKitSyncEngine, inventoryState: CKSyncEngine.State.Serialization?, markerState: CKSyncEngine.State.Serialization?)
    func ensureZones() async throws
    func fetchMarkers() async throws
    func fetchInventory() async throws
    func sendMarkers() async throws
    func sendInventory() async throws
    func queueInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange])
    func queueMarkers(_ changes: [CKSyncEngine.PendingRecordZoneChange])
    func removeInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange])
    func stop() async
}

@MainActor
final class CloudKitTransport: InventorySyncTransport {
    private let containerIdentifier: String
    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).privateCloudDatabase }
    private var inventory: CKSyncEngine?
    private var markers: CKSyncEngine?

    init(containerIdentifier: String) { self.containerIdentifier = containerIdentifier }

    func start(delegate: CloudKitSyncEngine, inventoryState: CKSyncEngine.State.Serialization?, markerState: CKSyncEngine.State.Serialization?) {
        var config = CKSyncEngine.Configuration(database: database, stateSerialization: markerState, delegate: delegate)
        config.automaticallySync = delegate.automaticSyncReady
        config.subscriptionID = "rInventoryDeletionMarkers_v3"
        markers = CKSyncEngine(config)
        config = CKSyncEngine.Configuration(database: database, stateSerialization: inventoryState, delegate: delegate)
        // One scheduler observes database changes. Inventory operations are ordered externally.
        config.automaticallySync = false
        config.subscriptionID = "rInventoryChanges_v3"
        inventory = CKSyncEngine(config)
        delegate.inventoryEngine = inventory
        delegate.markerEngine = markers
    }

    func ensureZones() async throws {
        let names = [SyncPersistence.itemsZone, SyncPersistence.categoriesZone, SyncPersistence.locationsZone, SyncPersistence.markersZone]
        let result = try await database.modifyRecordZones(saving: names.map { CKRecordZone(zoneName: $0) }, deleting: [])
        for (_, value) in result.saveResults { _ = try value.get() }
    }
    func fetchMarkers() async throws {
        guard let markers else { throw CloudKitSyncError.syncEngineNotInitialized }
        try await markers.fetchChanges(.init(scope: .zoneIDs([CKRecordZone.ID(zoneName: SyncPersistence.markersZone)])))
    }
    func fetchInventory() async throws {
        guard let inventory else { throw CloudKitSyncError.syncEngineNotInitialized }
        try await inventory.fetchChanges(.init(scope: .zoneIDs([
            CKRecordZone.ID(zoneName: SyncPersistence.itemsZone),
            CKRecordZone.ID(zoneName: SyncPersistence.categoriesZone),
            CKRecordZone.ID(zoneName: SyncPersistence.locationsZone)
        ])))
    }
    func sendMarkers() async throws { try await markers?.sendChanges() }
    func sendInventory() async throws { try await inventory?.sendChanges() }
    func queueInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { inventory?.state.add(pendingRecordZoneChanges: changes) }
    func queueMarkers(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { markers?.state.add(pendingRecordZoneChanges: changes) }
    func removeInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { inventory?.state.remove(pendingRecordZoneChanges: changes) }
    func stop() async {
        await inventory?.cancelOperations()
        await markers?.cancelOperations()
        inventory = nil; markers = nil
    }
}

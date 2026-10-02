import Testing
import Foundation
import SwiftData
import CloudKit
@testable import rInventory

enum CallbackContext {
    @TaskLocal static var insideDelegate = false
}

@MainActor
final class FakeSyncTransport: InventorySyncTransport {
    weak var delegate: CloudKitSyncEngine?
    var inventory = Set<CKSyncEngine.PendingRecordZoneChange>()
    var markers = Set<CKSyncEngine.PendingRecordZoneChange>()
    var events: [String] = []
    var remoteRecords: [CKRecord] = []
    var remoteMarkers: [CKRecord] = []
    var fetchError: Error?
    var sendError: Error?
    var onFetch: (() async throws -> Void)?
    var onSend: ((CKRecord) throws -> Void)?
    func start(delegate: CloudKitSyncEngine, inventoryState: CKSyncEngine.State.Serialization?, markerState: CKSyncEngine.State.Serialization?) {
        self.delegate = delegate; events.append("start")
    }
    func ensureZones() async throws { events.append("zones") }
    func fetchMarkers() async throws {
        #expect(!CallbackContext.insideDelegate)
        events.append("fetchMarkers")
        if let fetchError { throw fetchError }
        try await delegate?.ingest(records: remoteMarkers)
    }
    func fetchInventory() async throws {
        #expect(!CallbackContext.insideDelegate)
        events.append("fetchInventory")
        #expect(delegate?.inventoryCallbackMayProceed(isManual: true, sending: false) == true)
        try await onFetch?()
        try await delegate?.ingest(records: remoteRecords)
    }
    func sendMarkers() async throws {
        #expect(!CallbackContext.insideDelegate)
        events.append("sendMarkers")
        if let sendError { throw sendError }
        guard let delegate else { return }
        for change in markers {
            if case .saveRecord(let id) = change, let record = try await delegate.recordForSave(id) {
                try delegate.acknowledge(record)
                remoteMarkers.append(record)
            }
        }
        markers.removeAll()
        try delegate.modelContext.save()
    }
    func sendInventory() async throws {
        #expect(!CallbackContext.insideDelegate)
        events.append("sendInventory")
        if let sendError { throw sendError }
        guard let delegate else { return }
        let sending = inventory
        inventory.removeAll()
        for change in sending {
            switch change {
            case .saveRecord(let id):
                if let record = try await delegate.recordForSave(id) {
                    try onSend?(record)
                    try delegate.acknowledge(record)
                }
            case .deleteRecord(let id):
                let state = try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: delegate.modelContext)
                #expect(state.markerUploaded)
                state.recordDeleted = true
            @unknown default: break
            }
        }
        try delegate.modelContext.save()
        delegate.localChangesCommitted()
    }
    func queueInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { inventory.formUnion(changes) }
    func queueMarkers(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { markers.formUnion(changes) }
    func removeInventory(_ changes: [CKSyncEngine.PendingRecordZoneChange]) { inventory.subtract(changes) }
    func stop() async { events.append("stop"); inventory.removeAll(); markers.removeAll() }
}

@MainActor
final class FakeAccountProvider: InventoryAccountProvider {
    var current: String?
    var unavailable = false
    init(_ identity: String?) { current = identity }
    func identity() async throws -> String? {
        if unavailable { throw CloudKitSyncError.accountNotAvailable }
        return current
    }
}

@Suite(.serialized)
@MainActor
struct InventoryTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: SyncPersistence.schema, configurations: [ModelConfiguration(schema: SyncPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    private func record(_ id: UUID = UUID(), zone: String = SyncPersistence.itemsZone, name: String = "Remote", date: Date = Date(), revision: String = "remote") -> CKRecord {
        let type = zone == SyncPersistence.itemsZone ? "CD_Item" : zone == SyncPersistence.categoriesZone ? "CD_Category" : "CD_Location"
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: id.uuidString, zoneID: CKRecordZone.ID(zoneName: zone)))
        record["CD_name"] = name; record["CD_quantity"] = 3
        record["CD_modifiedDate"] = date; record["CD_revision"] = revision
        record["CD_id"] = id.uuidString
        return record
    }
    private func marker(_ id: UUID, zone: String = SyncPersistence.itemsZone) -> CKRecord {
        let record = CKRecord(recordType: "InventoryDeletion", recordID: CKRecord.ID(recordName: SyncRecordState.key(zone: zone, record: id.uuidString), zoneID: CKRecordZone.ID(zoneName: SyncPersistence.markersZone)))
        record["sourceZone"] = zone; record["sourceRecord"] = id.uuidString
        return record
    }

    @Test func emptyCategoryCleanupRespectsRetentionSetting() throws {
        let container = try store()
        let context = container.mainContext
        let category = Category(name: "Tools")
        context.insert(category)
        try SyncPersistence.save(context)
        category.checkAndCleanup(category: category, context: context, keepEmpty: true)
        try SyncPersistence.save(context)
        #expect(try context.fetch(FetchDescriptor<rInventory.Category>()).count == 1)
        category.checkAndCleanup(category: category, context: context, keepEmpty: false)
        try SyncPersistence.save(context)
        #expect(try context.fetch(FetchDescriptor<rInventory.Category>()).isEmpty)
    }

    @Test func emptyLocationCleanupRespectsRetentionSetting() throws {
        let container = try store()
        let context = container.mainContext
        let location = Location(name: "Garage")
        context.insert(location)
        try SyncPersistence.save(context)
        location.checkAndCleanup(location: location, context: context, keepEmpty: true)
        try SyncPersistence.save(context)
        #expect(try context.fetch(FetchDescriptor<Location>()).count == 1)
        location.checkAndCleanup(location: location, context: context, keepEmpty: false)
        try SyncPersistence.save(context)
        #expect(try context.fetch(FetchDescriptor<Location>()).isEmpty)
    }

    @Test func deletingCategoryKeepsItemsAndQueuesRelationshipRemoval() throws {
        let container = try store()
        let context = container.mainContext
        let category = Category(name: "Tools")
        let location = Location(name: "Garage")
        let item = Item(name: "Hammer", quantity: 1, location: location, category: category)
        context.insert(item)
        try SyncPersistence.save(context)
        category.deleteCategory(context: context)
        #expect(try context.fetch(FetchDescriptor<rInventory.Category>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Item>()).count == 1)
        #expect(item.category == nil)
        #expect(item.location?.id == location.id)
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: context)
        #expect(state.categoryID == nil)
        #expect(state.pendingSave)
    }

    @Test func deletingLocationDeletesOnlyItsItemsAndQueuesDeletions() throws {
        let container = try store()
        let context = container.mainContext
        let location = Location(name: "Garage")
        let removed = Item(name: "Hammer", quantity: 1, location: location)
        let kept = Item(name: "Book", quantity: 1, sortOrder: 1)
        let removedID = removed.id
        let locationID = location.id
        context.insert(removed)
        context.insert(kept)
        try SyncPersistence.save(context)
        location.deleteLocation(context: context)
        #expect(try context.fetch(FetchDescriptor<Location>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Item>()).map(\.id) == [kept.id])
        #expect(kept.sortOrder == 0)
        #expect(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: removedID.uuidString, context: context).deleted)
        #expect(try SyncPersistence.state(zone: SyncPersistence.locationsZone, record: locationID.uuidString, context: context).deleted)
    }

    @Test func editingMissingLocationDoesNotPersistDisplayFallback() async throws {
        let container = try store()
        let context = container.mainContext
        let item = Item(name: "Book", quantity: 1)
        context.insert(item)
        try SyncPersistence.save(context)
        #expect(LocationDisplay(item.location).name == "The Void")
        await item.updateItem(name: "Novel", locationName: "", context: context)
        #expect(item.location == nil)
        #expect(try context.fetch(FetchDescriptor<Location>()).isEmpty)
        #expect(LocationDisplay(item.location).name == "The Void")
    }

    @Test func firstDeviceDownloadsBeforeSendingAndCompletesBootstrap() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        transport.remoteRecords = [record()]
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, transport: transport)
        try engine.start(); await engine.manualSync()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Item>()) == 1)
        #expect(transport.events.firstIndex(of: "fetchMarkers")! < transport.events.firstIndex(of: "fetchInventory")!)
        #expect(transport.events.firstIndex(of: "fetchInventory")! < transport.events.firstIndex(of: "sendInventory")!)
        #expect(try SyncPersistence.checkpoint("bootstrap", context: container.mainContext).completed)
        #expect(engine.syncState == .success)
        #expect(transport.events.filter { $0 == "fetchMarkers" }.count == 2)
    }

    @Test func startupMutationSurvivesMissingEngineAndInterruptedBootstrap() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Offline", quantity: 1); context.insert(item)
        try SyncPersistence.save(context)
        let transport = FakeSyncTransport(); transport.fetchError = CKError(.networkFailure)
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync()
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: context)
        #expect(state.pendingSave)
        #expect(!(try SyncPersistence.checkpoint("bootstrap", context: context).completed))
        #expect(!transport.events.contains("sendInventory"))
        transport.fetchError = nil
        await engine.manualSync()
        #expect(!state.pendingSave)
        #expect(engine.syncState == .success)
    }

    @Test func olderFetchedRecordCannotOverwriteEditMadeDuringFetch() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Original", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let transport = FakeSyncTransport()
        transport.remoteRecords = [record(item.id, name: "Old cloud", date: Date(timeIntervalSince1970: 1))]
        transport.onFetch = { item.name = "During fetch"; try SyncPersistence.save(context) }
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync()
        #expect(item.name == "During fetch")
    }

    @Test func newerRemoteEditWinsAndClearsPendingSave() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Local", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let transport = FakeSyncTransport()
        transport.remoteRecords = [record(item.id, name: "Newer", date: Date().addingTimeInterval(100))]
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync()
        #expect(item.name == "Newer")
        #expect(!(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: context)).pendingSave)
    }

    @Test func revisionTieBreakIsDeterministic() {
        let date = Date()
        #expect(SyncPersistence.remoteWins(localDate: date, localRevision: "a", remoteDate: date, remoteRevision: "b"))
        #expect(!SyncPersistence.remoteWins(localDate: date, localRevision: "b", remoteDate: date, remoteRevision: "a"))
    }

    @Test func oldAcknowledgmentLeavesNewerRevisionPending() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "First", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: engine.itemsZoneID)
        let oldRecord = try #require(await engine.recordForSave(id))
        item.name = "Second"; try SyncPersistence.save(context)
        try engine.acknowledge(oldRecord)
        #expect(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: context).pendingSave)
    }

    @Test func deletionMarkerBeatsLaterOfflineEditAndFullResync() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Offline edit", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let id = item.id; let transport = FakeSyncTransport()
        transport.remoteMarkers = [marker(id)]
        transport.remoteRecords = [record(id, name: "Stale recreation", date: Date().addingTimeInterval(1000))]
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync(); await engine.forceFullResync()
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: id.uuidString, context: context).deleted)
    }

    @Test func deletionWaitsForMarkerAcknowledgmentAndRetries() async throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Delete", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let id = item.id; context.delete(item); try SyncPersistence.save(context)
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: id.uuidString, context: context)
        state.modifiedDate = Date().addingTimeInterval(-60 * 86400); try context.save()
        let transport = FakeSyncTransport(); transport.sendError = CKError(.networkFailure)
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync()
        #expect(state.deleted && !state.markerUploaded && !state.recordDeleted)
        #expect(!transport.inventory.contains(.deleteRecord(CKRecord.ID(recordName: id.uuidString, zoneID: engine.itemsZoneID))))
        transport.sendError = nil; await engine.manualSync()
        #expect(state.markerUploaded && state.recordDeleted)
        #expect(transport.events.firstIndex(of: "sendMarkers")! < transport.events.firstIndex(of: "sendInventory")!)
    }

    @Test func fetchedDeletionDoesNotEchoAcknowledgedDelete() async throws {
        let container = try store(); let context = container.mainContext; let id = UUID()
        let transport = FakeSyncTransport(); let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start()
        try await engine.ingest(records: [marker(id)], deletions: [CKRecord.ID(recordName: id.uuidString, zoneID: engine.itemsZoneID)])
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: id.uuidString, context: context)
        #expect(state.markerUploaded && state.recordDeleted)
        #expect(transport.inventory.isEmpty && transport.markers.isEmpty)
    }

    @Test func relationshipsResolveInEitherOrderAndNewerRemovalReplacesPendingRefs() async throws {
        let container = try store(); let context = container.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let itemID = UUID(), categoryID = UUID(), locationID = UUID()
        let itemRecord = record(itemID)
        itemRecord["CD_categoryID"] = categoryID.uuidString; itemRecord["CD_locationID"] = locationID.uuidString
        try await engine.ingest(records: [itemRecord])
        let item = try #require(context.fetch(FetchDescriptor<Item>()).first)
        #expect(item.category == nil && item.location == nil)
        try await engine.ingest(records: [record(categoryID, zone: SyncPersistence.categoriesZone), record(locationID, zone: SyncPersistence.locationsZone)])
        #expect(item.category?.id == categoryID && item.location?.id == locationID)
        let removal = record(itemID, date: Date().addingTimeInterval(1))
        try await engine.ingest(records: [removal])
        #expect(item.category == nil && item.location == nil)
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: itemID.uuidString, context: context)
        #expect(state.categoryID == nil && state.locationID == nil)
    }

    @Test func deletedRelationshipTargetCannotRelinkAndLegacyReferencesAreReadable() async throws {
        let container = try store(); let context = container.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let categoryID = UUID(); let itemRecord = record()
        itemRecord["CD_category"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: categoryID.uuidString, zoneID: engine.categoriesZoneID), action: .none)
        try await engine.ingest(records: [record(categoryID, zone: SyncPersistence.categoriesZone), itemRecord])
        let item = try #require(context.fetch(FetchDescriptor<Item>()).first)
        #expect(item.category?.id == categoryID)
        try await engine.ingest(records: [marker(categoryID, zone: SyncPersistence.categoriesZone)])
        try await engine.ingest(records: [itemRecord])
        #expect(item.category == nil)
    }

    @Test func imagesAndSymbolsCanBeReplacedAndRemoved() async throws {
        let container = try store(); let context = container.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let id = UUID(); let image = record(id); image["CD_imageData"] = Data([1, 2]); image["CD_symbol"] = "box"
        try await engine.ingest(records: [image])
        let item = try #require(context.fetch(FetchDescriptor<Item>()).first)
        let symbol = record(id); symbol["CD_symbol"] = "star"
        try await engine.ingest(records: [symbol])
        #expect(item.imageData == nil && item.symbol == "star")
        try await engine.ingest(records: [record(id)])
        #expect(item.imageData == nil && item.symbol == nil && item.symbolColorData == nil)
    }

    @Test func invalidAssetDoesNotEraseExistingImage() async throws {
        let container = try store(); let context = container.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let id = UUID(); let first = record(id); first["CD_imageData"] = Data([1, 2])
        try await engine.ingest(records: [first])
        let invalid = record(id); invalid["CD_imageAsset"] = CKAsset(fileURL: URL(fileURLWithPath: "/tmp/nonexistent-inventory-test-\(UUID())"))
        do { try await engine.ingest(records: [invalid]); Issue.record("Expected asset failure") } catch {}
        #expect(try context.fetch(FetchDescriptor<Item>()).first?.imageData == Data([1, 2]))
    }

    @Test func watchNeverQueuesUploadsAndUnchangedFetchDoesNotDirtyInventory() async throws {
        let container = try store(); let context = container.mainContext; let transport = FakeSyncTransport()
        transport.remoteRecords = [record()]
        let engine = CloudKitSyncEngine(modelContext: context, mode: .downloadOnly, transport: transport)
        try engine.start(); await engine.manualSync()
        let item = try #require(context.fetch(FetchDescriptor<Item>()).first)
        let modelID = item.persistentModelID
        await engine.manualSync()
        #expect(transport.inventory.isEmpty && transport.markers.isEmpty)
        #expect(!transport.events.contains("zones") && !transport.events.contains("sendInventory") && !transport.events.contains("sendMarkers"))
        #expect(try context.fetch(FetchDescriptor<Item>()).first?.persistentModelID == modelID)
        #expect(!context.hasChanges)
    }

    @Test func visibilityAndReorderMutationsAreQueuedTogether() throws {
        let container = try store(); let context = container.mainContext
        let category = Category(name: "Category"), location = Location(name: "Location")
        context.insert(category); context.insert(location); try SyncPersistence.save(context)
        category.displayInRow.toggle(); category.sortOrder = 4; location.displayInRow.toggle(); location.sortOrder = 2
        try SyncPersistence.save(context)
        #expect(try SyncPersistence.state(zone: SyncPersistence.categoriesZone, record: category.id.uuidString, context: context).pendingSave)
        #expect(try SyncPersistence.state(zone: SyncPersistence.locationsZone, record: location.id.uuidString, context: context).pendingSave)
        #expect(!category.revision.isEmpty && !location.revision.isEmpty)
    }

    @Test func failedCommitRollsBackMutationAndOutbox() throws {
        let container = try store(); let context = container.mainContext
        let item = Item(name: "Committed", quantity: 1); context.insert(item); try SyncPersistence.save(context)
        let revision = item.revision
        item.name = "Uncommitted"
        do {
            try SyncPersistence.save(context, commit: { _ in throw CKError(.internalError) })
            Issue.record("Expected commit failure")
        } catch {}
        #expect(item.name == "Committed" && item.revision == revision)
        #expect(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: context).revision == revision)
    }

    @Test func watchVisibilityIsLocalPersistentAndAccountScoped() throws {
        let container = try store(); let context = container.mainContext
        let category = Category(name: "Category"); context.insert(category); try context.save()
        let suite = "visibility-tests-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = WatchVisibilityPreferences(defaults: defaults)
        visibility.activate(accountKey: "A", context: context)
        visibility.toggle(zone: SyncPersistence.categoriesZone, id: category.id, fallback: category.displayInRow)
        #expect(category.displayInRow && !context.hasChanges)
        let restored = WatchVisibilityPreferences(defaults: defaults); restored.activate(accountKey: "A", context: context)
        #expect(!restored.visible(zone: SyncPersistence.categoriesZone, id: category.id, fallback: true))
        restored.activate(accountKey: "B", context: context)
        #expect(restored.visible(zone: SyncPersistence.categoriesZone, id: category.id, fallback: true))
    }

    @Test func accountsAndOfflineImportRemainIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("account-tests-\(UUID())", isDirectory: true)
        let suite = "account-tests-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let account = FakeAccountProvider(nil)
        let coordinator = InventoryStoreCoordinator(directory: directory, defaults: defaults, accountProvider: account, transportFactory: { FakeSyncTransport() })
        await coordinator.refreshAccount(force: true)
        let offlineID = UUID(); coordinator.container.mainContext.insert(Item(offlineID, name: "Offline", quantity: 1))
        try SyncPersistence.save(coordinator.container.mainContext)
        account.current = "A"; await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(coordinator.hasOfflineInventory)
        try coordinator.importOfflineInventory(); try coordinator.importOfflineInventory()
        let imported = try #require(coordinator.container.mainContext.fetch(FetchDescriptor<Item>()).first)
        #expect(imported.id != offlineID)
        #expect(try coordinator.container.mainContext.fetchCount(FetchDescriptor<Item>()) == 1)
        account.current = "B"; await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetchCount(FetchDescriptor<Item>()) == 0)
        account.current = "A"; await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetchCount(FetchDescriptor<Item>()) == 1)
        account.current = nil; await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetch(FetchDescriptor<Item>()).first?.id == offlineID)
    }

    @Test func refreshesCoalesceAndTemporaryAccountFailureCanRecover() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refresh-tests-\(UUID())")
        let suite = "refresh-tests-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let account = FakeAccountProvider("A"); let transport = FakeSyncTransport()
        let coordinator = InventoryStoreCoordinator(directory: directory, defaults: defaults, accountProvider: account, transportFactory: { transport })
        async let first: Void = coordinator.refreshAccount()
        async let second: Void = coordinator.refreshAccount()
        _ = await (first, second)
        #expect(transport.events.filter { $0 == "fetchInventory" }.count == 1)
        account.unavailable = true; await coordinator.refreshAccount(force: true)
        #expect(coordinator.errorMessage != nil && !coordinator.engine.isAccountAvailable)
        account.unavailable = false; await coordinator.refreshAccount(force: true)
        #expect(coordinator.engine.isAccountAvailable && coordinator.errorMessage == nil)
    }
    @Test func pendingOutboxAndOldDeletionSurviveDiskRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restart-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("inventory.store")
        let itemID = UUID(), deletedID = UUID()
        do {
            let container = try ModelContainer(for: SyncPersistence.schema, configurations: [ModelConfiguration(schema: SyncPersistence.schema, url: url, cloudKitDatabase: .none)])
            let context = container.mainContext
            context.autosaveEnabled = false
            context.insert(Item(itemID, name: "Pending", quantity: 2))
            let deleted = Item(deletedID, name: "Deleted", quantity: 1); context.insert(deleted)
            try SyncPersistence.save(context)
            context.delete(deleted); try SyncPersistence.save(context)
            try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: deletedID.uuidString, context: context).modifiedDate = Date().addingTimeInterval(-60 * 86400)
            try context.save()
        }
        let reopened = try ModelContainer(for: SyncPersistence.schema, configurations: [ModelConfiguration(schema: SyncPersistence.schema, url: url, cloudKitDatabase: .none)])
        let transport = FakeSyncTransport(); let context = reopened.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, transport: transport)
        try engine.start(); await engine.manualSync()
        #expect(try context.fetch(FetchDescriptor<Item>()).first?.id == itemID)
        #expect(!(try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: itemID.uuidString, context: context)).pendingSave)
        let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: deletedID.uuidString, context: context)
        #expect(state.deleted && state.markerUploaded && state.recordDeleted)
    }

    @Test func legacyStoreAndTombstonesAreAdoptedOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "legacy-tests-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let keepID = UUID(), deletedID = UUID()
        do {
            // Opening the former three-model schema exercises additive local metadata migration.
            let schema = Schema([Item.self, Category.self, Location.self])
            let legacy = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("rInventory.store"), cloudKitDatabase: .none)])
            legacy.mainContext.insert(Item(keepID, name: "Legacy", quantity: 1))
            legacy.mainContext.insert(Item(deletedID, name: "Old tombstone", quantity: 1))
            try legacy.mainContext.save()
        }
        struct Tombstone: Encodable { let recordName: String; let zoneName: String; let timestamp: Date }
        defaults.set(try JSONEncoder().encode([deletedID.uuidString: Tombstone(recordName: deletedID.uuidString, zoneName: SyncPersistence.itemsZone, timestamp: Date().addingTimeInterval(-60 * 86400))]), forKey: "CloudKitTombstones_v2")
        let account = FakeAccountProvider("A")
        let coordinator = InventoryStoreCoordinator(directory: directory, defaults: defaults, accountProvider: account, transportFactory: { FakeSyncTransport() })
        await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetch(FetchDescriptor<Item>()).map(\.id) == [keepID])
        #expect(defaults.string(forKey: "InventoryLegacyOwner_v3") == InventoryStoreCoordinator.accountKey("A"))
        account.current = "B"; await coordinator.refreshAccount(force: true)
        #expect(try coordinator.container.mainContext.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("rInventory.store").path))
    }

    @Test func allRelationshipsWriteUUIDFieldsAndAssetUploadFilesSurviveUntilStop() async throws {
        let container = try store(); let context = container.mainContext
        let category = Category(name: "Category"), location = Location(name: "Location")
        context.insert(category); context.insert(location)
        let item = Item(name: "Large image", quantity: 1, location: location, category: category, imageData: Data(repeating: 1, count: 600_000))
        context.insert(item); try SyncPersistence.save(context)
        let engine = CloudKitSyncEngine(modelContext: context, transport: FakeSyncTransport())
        let record = try #require(await engine.recordForSave(CKRecord.ID(recordName: item.id.uuidString, zoneID: engine.itemsZoneID)))
        #expect(record["CD_locationID"] as? String == location.id.uuidString)
        #expect(record["CD_categoryID"] as? String == category.id.uuidString)
        #expect(record["CD_location"] == nil && record["CD_category"] == nil)
        let asset = try #require(record["CD_imageAsset"] as? CKAsset); let url = try #require(asset.fileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        await engine.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unchangedRevisionAvoidsReadingAssetAgain() async throws {
        let container = try store(); let context = container.mainContext
        let engine = CloudKitSyncEngine(modelContext: context, mode: .downloadOnly, transport: FakeSyncTransport())
        let first = record(); first["CD_imageData"] = Data([1, 2])
        try await engine.ingest(records: [first])
        let repeated = record(UUID(uuidString: first.recordID.recordName)!, date: first["CD_modifiedDate"] as! Date)
        repeated["CD_imageAsset"] = CKAsset(fileURL: URL(fileURLWithPath: "/tmp/unchanged-asset-\(UUID())"))
        try await engine.ingest(records: [repeated])
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Item>()).first?.imageData == Data([1, 2]))
    }

    @Test func automaticDelegateDefersNetworkWorkAndDropsCallbackContext() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, transport: transport)
        try engine.start()
        CallbackContext.$insideDelegate.withValue(true) {
            engine.beginAutomaticFetch()
            engine.finishAutomaticFetch()
            #expect(!engine.inventoryCallbackMayProceed(isManual: false, sending: true))
            #expect(!transport.events.contains("fetchMarkers"))
        }
        let scheduled = try #require(engine.scheduledSyncTask)
        await scheduled.value
        #expect(transport.events.filter { $0 == "fetchInventory" }.count == 1)
        #expect(engine.syncState == .success)
        await engine.stop()
    }

    @Test func automaticDownloadsReconcileMarkersWithoutFeedbackLoop() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, mode: .downloadOnly, transport: transport)
        try engine.start(); await engine.manualSync()
        let id = UUID()
        let record = CKRecord(recordType: "CD_Item", recordID: CKRecord.ID(recordName: id.uuidString, zoneID: engine.itemsZoneID))
        record["CD_name"] = "Deleted remotely" as CKRecordValue
        let marker = CKRecord(recordType: "InventoryDeletion", recordID: CKRecord.ID(recordName: "\(SyncPersistence.itemsZone)|\(id.uuidString)", zoneID: engine.markersZoneID))
        marker["sourceZone"] = SyncPersistence.itemsZone as CKRecordValue
        marker["sourceRecord"] = id.uuidString as CKRecordValue
        transport.remoteMarkers = [marker]
        let previousFetches = transport.events.filter { $0 == "fetchInventory" }.count
        CallbackContext.$insideDelegate.withValue(true) {
            engine.beginAutomaticFetch()
            engine.stageAutomaticInventory(records: [record], deletions: [])
            engine.finishAutomaticFetch()
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<Item>()).isEmpty)
        let scheduled = try #require(engine.scheduledSyncTask)
        await scheduled.value
        #expect(try container.mainContext.fetch(FetchDescriptor<Item>()).isEmpty)
        #expect(transport.events.filter { $0 == "fetchInventory" }.count == previousFetches + 1)
        // Manual marker completion must not initiate another ordered refresh.
        engine.finishAutomaticFetch()
        #expect(engine.scheduledSyncTask == nil)
        #expect(engine.syncState == .success)
        await engine.stop()
    }

    @Test func automaticFetchIgnoresUnrelatedCloudKitZones() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, mode: .downloadOnly, transport: transport)
        try engine.start(); await engine.manualSync()
        let unrelated = CKRecord(recordType: "CD_Item", recordID: CKRecord.ID(recordName: "legacy-record", zoneID: CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")))
        let valid = record()
        engine.beginAutomaticFetch()
        engine.stageAutomaticInventory(records: [unrelated, valid], deletions: [unrelated.recordID])
        engine.finishAutomaticFetch()
        let scheduled = try #require(engine.scheduledSyncTask)
        await scheduled.value
        #expect(engine.syncState == .success)
        #expect(try container.mainContext.fetch(FetchDescriptor<Item>()).map(\.id) == [UUID(uuidString: valid.recordID.recordName)!])
        await engine.stop()
    }

    @Test func repairDiscardsFailedStagedBatchAndFetchesFreshRecords() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, mode: .downloadOnly, transport: transport)
        try engine.start(); await engine.manualSync()
        let invalid = record(); invalid["CD_quantity"] = nil
        engine.stageAutomaticInventory(records: [invalid], deletions: [])
        await engine.manualSync()
        if case .error = engine.syncState {} else { Issue.record("Expected failed staged batch") }
        transport.remoteRecords = [record(UUID(uuidString: invalid.recordID.recordName)!)]
        await engine.forceFullResync()
        #expect(engine.syncState == .success)
        #expect(try container.mainContext.fetch(FetchDescriptor<Item>()).first?.quantity == 3)
        await engine.stop()
    }

    @Test func initialSignInEventsDoNotCancelVerifiedAccountSync() async throws {
        let container = try store(); let transport = FakeSyncTransport()
        let engine = CloudKitSyncEngine(modelContext: container.mainContext, transport: transport)
        var invalidations = 0
        engine.accountDidChange = { invalidations += 1 }
        try engine.start(accountIdentity: "A")
        transport.onFetch = {
            // Both native engines may announce the current account on initialization.
            engine.handleAccountChange(.signIn(currentUser: CKRecord.ID(recordName: "A")))
            engine.handleAccountChange(.signIn(currentUser: CKRecord.ID(recordName: "A")))
            #expect(!engine.stopped && engine.isAccountAvailable)
        }
        await engine.manualSync()
        #expect(engine.syncState == .success)
        #expect(invalidations == 0)
        // A real change still blocks all old-account work immediately and notifies once.
        engine.handleAccountChange(.switchAccounts(previousUser: CKRecord.ID(recordName: "A"), currentUser: CKRecord.ID(recordName: "B")))
        engine.handleAccountChange(.signIn(currentUser: CKRecord.ID(recordName: "B")))
        #expect(engine.stopped && !engine.isAccountAvailable)
        #expect(invalidations == 1)
        await engine.stop()
    }

    @Test func forcedSameAccountRefreshKeepsEngineAndCoalescesDuringSync() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("account-events-\(UUID())")
        let suite = "account-events-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let account = FakeAccountProvider("A"); let transport = FakeSyncTransport()
        var factories = 0
        let coordinator = InventoryStoreCoordinator(directory: directory, defaults: defaults, accountProvider: account, transportFactory: {
            factories += 1; return transport
        })
        var notifications: [Task<Void, Never>] = []
        transport.onFetch = {
            coordinator.engine.handleAccountChange(.signIn(currentUser: CKRecord.ID(recordName: "A")))
            notifications.append(Task { await coordinator.refreshAccount(force: true) })
            await Task.yield()
        }
        await coordinator.refreshAccount()
        for notification in notifications { await notification.value }
        transport.onFetch = nil
        let engine = coordinator.engine
        let factoriesBefore = factories
        let stopsBefore = transport.events.filter { $0 == "stop" }.count
        let fetchesBefore = transport.events.filter { $0 == "fetchInventory" }.count
        for _ in 0..<3 { await coordinator.refreshAccount(force: true) }
        #expect(coordinator.engine === engine)
        #expect(factories == factoriesBefore)
        #expect(transport.events.filter { $0 == "stop" }.count == stopsBefore)
        #expect(fetchesBefore == 1)
        #expect(coordinator.engine.syncState == .success)
        await engine.stop()
    }

}

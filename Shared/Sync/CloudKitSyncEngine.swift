import Foundation
import CloudKit
import SwiftData
import Combine
import os

public enum SyncState: Equatable {
    case idle, syncing, success, error(String)
}

/// Native scheduling requests an ordered sync outside delegate callbacks. Delegates only
/// select scopes and prepare records; they never await another CKSyncEngine operation.
@MainActor
public final class CloudKitSyncEngine: ObservableObject {
    public static weak var shared: CloudKitSyncEngine?
    enum Mode { case readWrite, downloadOnly }
    @Published public private(set) var syncState: SyncState = .idle
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var isAccountAvailable = false
    let modelContext: ModelContext
    let mode: Mode
    let itemsZoneID = CKRecordZone.ID(zoneName: SyncPersistence.itemsZone)
    let categoriesZoneID = CKRecordZone.ID(zoneName: SyncPersistence.categoriesZone)
    let locationsZoneID = CKRecordZone.ID(zoneName: SyncPersistence.locationsZone)
    let markersZoneID = CKRecordZone.ID(zoneName: SyncPersistence.markersZone)
    weak var inventoryEngine: CKSyncEngine?
    weak var markerEngine: CKSyncEngine?
    private let transport: any InventorySyncTransport
    private var currentSyncTask: Task<Void, Never>?
    private(set) var scheduledSyncTask: Task<Void, Never>?
    private var inventorySendPermitted = false
    private var automaticFetchInProgress = false
    private var automaticFetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var stagedRecords: [CKRecord] = []
    private var stagedDeletions: [CKRecord.ID] = []
    private var deferredMarkerState: Data?
    private(set) var stopped = false
    private var verifiedAccountIdentity: String?
    private var started = false
    private(set) var automaticSyncReady = false
    private var operationError: Error?
    private var needsTokenReset = false
    private var markersFetchedForRefresh = false
    private var sentAssets: [CKRecord.ID: URL] = [:]
    var accountDidChange: (() -> Void)?
    private let logger = Logger(subsystem: "com.lagera.Inventory", category: "CloudKitSync")

    init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.lagera.Inventory", mode: Mode = .readWrite,
         transport: (any InventorySyncTransport)? = nil) {
        self.modelContext = modelContext
        self.mode = mode
        self.transport = transport ?? CloudKitTransport(containerIdentifier: containerIdentifier)
        if mode == .readWrite { Self.shared = self }
    }

    /// Account identity must be verified by the store coordinator before networking starts.
    func start(accountIdentity: String? = nil) throws {
        guard !started, !stopped else { return }
        verifiedAccountIdentity = accountIdentity
        isAccountAvailable = true
        try migrateLegacyState()
        let deleted = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.deleted })
        for state in try modelContext.fetch(deleted) {
            try applyDeletion(recordID(state), markerUploaded: state.markerUploaded, recordDeleted: state.recordDeleted)
        }
        if modelContext.hasChanges { try modelContext.save() }
        needsTokenReset = try SyncPersistence.checkpoint("needsTokenReset", context: modelContext).completed
        let bootstrapCompleted = try SyncPersistence.checkpoint("bootstrap", context: modelContext).completed
        automaticSyncReady = !needsTokenReset && bootstrapCompleted
        let inventoryState = needsTokenReset ? nil : try serialization("inventoryState")
        let markerState = needsTokenReset ? nil : try serialization("markerState")
        transport.start(delegate: self, inventoryState: inventoryState, markerState: markerState)
        started = true
        localChangesCommitted()
    }

    private func serialization(_ key: String) throws -> CKSyncEngine.State.Serialization? {
        let checkpoint = try SyncPersistence.checkpoint(key, context: modelContext)
        guard let data = checkpoint.data else { return nil }
        do { return try PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data) }
        catch { checkpoint.data = nil; try modelContext.save(); return nil }
    }

    func stop() async {
        stopped = true
        isAccountAvailable = false
        scheduledSyncTask?.cancel()
        currentSyncTask?.cancel()
        finishAutomaticFetch(schedule: false)
        await transport.stop()
        if let currentSyncTask { await currentSyncTask.value }
        cleanupAssets()
    }

    /// A fresh CKSyncEngine can report sign-in for the account we just verified.
    /// Only a different identity (or sign-out) invalidates this account's context.
    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        let currentIdentity: String?
        switch change {
        case .signIn(let currentUser): currentIdentity = currentUser.recordName
        case .switchAccounts(_, let currentUser): currentIdentity = currentUser.recordName
        case .signOut: currentIdentity = nil
        @unknown default: currentIdentity = nil
        }
        if let currentIdentity, currentIdentity == verifiedAccountIdentity { return }
        guard !stopped else { return }
        stopped = true
        isAccountAvailable = false
        accountDidChange?()
    }

    func report(_ error: Error) {
        operationError = error
        syncState = .error(error.localizedDescription)
        logger.error("Sync failed: \(error.localizedDescription)")
    }

    public func manualSync() async { await refresh(reset: false) }
    public func forceFullResync() async { await refresh(reset: true) }

    private func refresh(reset: Bool) async {
        if let task = currentSyncTask {
            await task.value
            if !reset { return }
        }
        guard isAccountAvailable, started, !stopped else {
            if !stopped { syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription) }
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.currentSyncTask = nil; self.inventorySendPermitted = false }
            self.operationError = nil
            self.markersFetchedForRefresh = false
            self.syncState = .syncing
            do {
                if !reset && self.mode == .readWrite {
                    for zone in [self.itemsZoneID, self.categoriesZoneID, self.locationsZoneID, self.markersZoneID] {
                        if try SyncPersistence.checkpoint("removedZone_\(zone.zoneName)", context: self.modelContext).completed {
                            throw CloudKitSyncError.zoneRemoved
                        }
                    }
                }
                if reset {
                    for zone in [self.itemsZoneID, self.categoriesZoneID, self.locationsZoneID, self.markersZoneID] {
                        let removed = try SyncPersistence.checkpoint("removedZone_\(zone.zoneName)", context: self.modelContext)
                        if removed.completed {
                            let states = try self.modelContext.fetch(FetchDescriptor<SyncRecordState>())
                            for state in states {
                                if self.mode == .readWrite && zone == self.markersZoneID && state.deleted { state.markerUploaded = false }
                                if state.zoneName == zone.zoneName {
                                    state.systemFields = nil
                                    if self.mode == .readWrite && !state.deleted { state.pendingSave = true }
                                }
                            }
                            removed.completed = false
                        }
                    }
                    try self.modelContext.save()
                }
                if reset || self.needsTokenReset {
                    await self.transport.stop()
                    try Task.checkCancellation()
                    for key in ["inventoryState", "markerState"] {
                        try SyncPersistence.checkpoint(key, context: self.modelContext).data = nil
                    }
                    try self.modelContext.save()
                    self.automaticSyncReady = false
                    self.transport.start(delegate: self, inventoryState: nil, markerState: nil)
                    self.needsTokenReset = false
                    try SyncPersistence.checkpoint("needsTokenReset", context: self.modelContext).completed = false
                    try self.modelContext.save()
                }
                if self.mode == .readWrite {
                    let zones = try SyncPersistence.checkpoint("zonesConfirmed", context: self.modelContext)
                    if !zones.completed || reset {
                        try await self.transport.ensureZones()
                        zones.completed = true
                        try self.modelContext.save()
                    }
                }
                await self.waitForAutomaticFetch()
                try Task.checkCancellation()
                try await self.fetchDeletionMarkers()
                try await self.applyStagedInventory()
                try Task.checkCancellation()
                try await self.transport.fetchInventory()
                if let error = self.operationError { throw error }
                try self.resolveRelationships()
                let bootstrap = try SyncPersistence.checkpoint("bootstrap", context: self.modelContext)
                if !bootstrap.completed { bootstrap.completed = true }
                if self.modelContext.hasChanges { try self.modelContext.save() }
                self.localChangesCommitted()
                if self.mode == .readWrite {
                    try await self.transport.sendMarkers()
                    if let error = self.operationError { throw error }
                    self.localChangesCommitted()
                    try await self.fetchDeletionMarkers()
                    self.inventorySendPermitted = true
                    try await self.transport.sendInventory()
                    self.inventorySendPermitted = false
                }
                await self.waitForAutomaticFetch()
                try Task.checkCancellation()
                if !self.stagedRecords.isEmpty || !self.stagedDeletions.isEmpty {
                    try await self.fetchDeletionMarkers()
                    try await self.applyStagedInventory()
                }
                if let error = self.operationError { throw error }
                let pending = try self.modelContext.fetch(FetchDescriptor<SyncRecordState>()).contains {
                    $0.pendingSave || ($0.deleted && (!$0.markerUploaded || !$0.recordDeleted))
                }
                if !self.automaticSyncReady {
                    // Only enable background scheduling after a successful, ordered bootstrap.
                    await self.transport.stop()
                    try Task.checkCancellation()
                    guard !self.stopped else { throw CancellationError() }
                    self.automaticSyncReady = true
                    self.transport.start(delegate: self, inventoryState: try self.serialization("inventoryState"), markerState: try self.serialization("markerState"))
                    self.localChangesCommitted()
                }
                self.lastSyncDate = Date()
                self.syncState = pending && self.mode == .readWrite ? .idle : .success
            } catch is CancellationError {
                self.syncState = .idle
            } catch let error as CKError where error.code == .operationCancelled {
                self.syncState = .idle
            } catch { self.report(error) }
        }
        currentSyncTask = task
        await task.value
    }

    private func fetchDeletionMarkers() async throws {
        do {
            try await transport.fetchMarkers()
            if let operationError { throw operationError }
            markersFetchedForRefresh = true
        } catch let error as CKError where error.code == .zoneNotFound && mode == .downloadOnly {
            // A new account may not have been initialized by a writable device yet.
            operationError = nil
            markersFetchedForRefresh = true
        }
    }

    /// Synchronous gate used by delegates. No CKSyncEngine operations may be awaited here,
    /// even on another engine sharing this delegate. A detached task drops CloudKit's
    /// callback task-local context and runs after the delegate has returned.
    func inventoryCallbackMayProceed(isManual: Bool, sending: Bool) -> Bool {
        guard started, !stopped else { return false }
        if isManual && currentSyncTask != nil && markersFetchedForRefresh && (!sending || inventorySendPermitted) { return true }
        return false
    }

    // The automatic engine downloads every changed zone, so CloudKit can advance its
    // database token without an empty-scope retry. Inventory waits for marker preflight.
    func beginAutomaticFetch() { automaticFetchInProgress = true }

    func stageAutomaticInventory(records: [CKRecord], deletions: [CKRecord.ID]) {
        stagedRecords.append(contentsOf: records)
        stagedDeletions.append(contentsOf: deletions)
    }

    func finishAutomaticFetch(schedule: Bool = true) {
        let wasAutomatic = automaticFetchInProgress
        automaticFetchInProgress = false
        let waiters = automaticFetchWaiters
        automaticFetchWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if wasAutomatic && schedule { requestScheduledSync() }
    }

    private func waitForAutomaticFetch() async {
        if automaticFetchInProgress {
            await withCheckedContinuation { automaticFetchWaiters.append($0) }
        }
    }

    private func applyStagedInventory() async throws {
        if !stagedRecords.isEmpty || !stagedDeletions.isEmpty {
            try await ingest(records: stagedRecords, deletions: stagedDeletions)
            stagedRecords.removeAll()
            stagedDeletions.removeAll()
        }
        if let data = deferredMarkerState {
            try SyncPersistence.checkpoint("markerState", context: modelContext).data = data
            try modelContext.save()
            deferredMarkerState = nil
        }
    }

    private func requestScheduledSync() {
        guard scheduledSyncTask == nil, currentSyncTask == nil, started, !stopped else { return }
        scheduledSyncTask = Task.detached { [weak self] in
            await self?.performScheduledSync()
        }
    }

    private func performScheduledSync() async {
        defer { scheduledSyncTask = nil }
        guard !Task.isCancelled, !stopped else { return }
        await manualSync()
    }

    func localChangesCommitted() {
        guard started, !stopped, mode == .readWrite else { return }
        do {
            let states = try modelContext.fetch(FetchDescriptor<SyncRecordState>())
            let bootstrap = try SyncPersistence.checkpoint("bootstrap", context: modelContext).completed
            var inventoryChanges: [CKSyncEngine.PendingRecordZoneChange] = []
            var markerChanges: [CKSyncEngine.PendingRecordZoneChange] = []
            for state in states {
                let id = recordID(state)
                if state.deleted {
                    transport.removeInventory([.saveRecord(id)])
                    if !state.markerUploaded { markerChanges.append(.saveRecord(markerID(state))) }
                    else if !state.recordDeleted { inventoryChanges.append(.deleteRecord(id)) }
                } else if state.pendingSave && bootstrap { inventoryChanges.append(.saveRecord(id)) }
            }
            transport.queueMarkers(markerChanges)
            transport.queueInventory(inventoryChanges)
            if bootstrap && (!inventoryChanges.isEmpty || !markerChanges.isEmpty) { requestScheduledSync() }
        } catch { report(error) }
    }

    private func recordID(_ state: SyncRecordState) -> CKRecord.ID {
        CKRecord.ID(recordName: state.recordName, zoneID: CKRecordZone.ID(zoneName: state.zoneName))
    }
    private func markerID(_ state: SyncRecordState) -> CKRecord.ID { CKRecord.ID(recordName: state.key, zoneID: markersZoneID) }

    /// Adopt only data in the verified account's store. Old defaults are read once by the coordinator.
    private func migrateLegacyState() throws {
        let migration = try SyncPersistence.checkpoint("outboxMigration", context: modelContext)
        guard !migration.completed else { return }
        if mode == .readWrite {
            for item in try modelContext.fetch(FetchDescriptor<Item>()) {
                let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: item.id.uuidString, context: modelContext)
                if !state.deleted {
                    state.pendingSave = true; state.revision = item.revision; state.modifiedDate = item.modifiedDate
                    if state.locationID == nil { state.locationID = item.location?.id }
                    if state.categoryID == nil { state.categoryID = item.category?.id }
                    state.needsRelationshipResolution = true
                }
            }
            for category in try modelContext.fetch(FetchDescriptor<Category>()) {
                let state = try SyncPersistence.state(zone: SyncPersistence.categoriesZone, record: category.id.uuidString, context: modelContext)
                if !state.deleted { state.pendingSave = true; state.revision = category.revision; state.modifiedDate = category.modifiedDate }
            }
            for location in try modelContext.fetch(FetchDescriptor<Location>()) {
                let state = try SyncPersistence.state(zone: SyncPersistence.locationsZone, record: location.id.uuidString, context: modelContext)
                if !state.deleted { state.pendingSave = true; state.revision = location.revision; state.modifiedDate = location.modifiedDate }
            }
        }
        migration.completed = true
        try modelContext.save()
    }

    private func item(_ id: UUID) throws -> Item? {
        var d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func category(_ id: UUID) throws -> Category? {
        var d = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
    private func location(_ id: UUID) throws -> Location? {
        var d = FetchDescriptor<Location>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func archive(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
    private func restoredRecord(_ state: SyncRecordState, type: String, id: CKRecord.ID) throws -> CKRecord {
        if let data = state.systemFields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            if let record = CKRecord(coder: decoder), record.recordID == id { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    func recordForSave(_ id: CKRecord.ID) async throws -> CKRecord? {
        if id.zoneID == markersZoneID {
            let key = id.recordName
            let descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.key == key })
            guard let state = try modelContext.fetch(descriptor).first, state.deleted else { return nil }
            let record = CKRecord(recordType: "InventoryDeletion", recordID: id)
            record["sourceZone"] = state.zoneName
            record["sourceRecord"] = state.recordName
            return record
        }
        guard mode == .readWrite, let uuid = UUID(uuidString: id.recordName) else { return nil }
        let state = try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext)
        guard !state.deleted, state.pendingSave else { return nil }
        let saveDate = state.modifiedDate
        let saveRevision = state.revision
        let record: CKRecord
        switch id.zoneID {
        case itemsZoneID:
            guard let item = try item(uuid) else { return nil }
            record = try restoredRecord(state, type: "CD_Item", id: id)
            record["CD_name"] = item.name; record["CD_quantity"] = item.quantity
            record["CD_sortOrder"] = item.sortOrder; record["CD_itemCreationDate"] = item.itemCreationDate
            record["CD_symbol"] = item.symbol; record["CD_symbolColorData"] = item.symbolColorData
            record["CD_locationID"] = state.locationID?.uuidString
            record["CD_categoryID"] = state.categoryID?.uuidString
            record["CD_location"] = nil; record["CD_category"] = nil
            record["location"] = nil; record["category"] = nil
            record["CD_imageData"] = nil; record["CD_imageAsset"] = nil
            if let data = item.imageData, !data.isEmpty {
                if data.count > 500_000 {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("inventory-\(UUID().uuidString).asset")
                    try await Task.detached(priority: .utility) { try data.write(to: url, options: .atomic) }.value
                    if let previous = sentAssets[id] { try? FileManager.default.removeItem(at: previous) }
                    sentAssets[id] = url
                    record["CD_imageAsset"] = CKAsset(fileURL: url)
                } else { record["CD_imageData"] = data }
            }
        case categoriesZoneID:
            guard let category = try category(uuid) else { return nil }
            record = try restoredRecord(state, type: "CD_Category", id: id)
            record["CD_name"] = category.name; record["CD_sortOrder"] = category.sortOrder
            record["CD_displayInRow"] = category.displayInRow
        case locationsZoneID:
            guard let location = try location(uuid) else { return nil }
            record = try restoredRecord(state, type: "CD_Location", id: id)
            record["CD_name"] = location.name; record["CD_sortOrder"] = location.sortOrder
            record["CD_displayInRow"] = location.displayInRow; record["CD_colorData"] = location.colorData
        default: return nil
        }
        record["CD_id"] = id.recordName
        record["CD_modifiedDate"] = saveDate
        record["CD_revision"] = saveRevision
        return record
    }

    private func referenceID(_ record: CKRecord, newKey: String, oldKey: String) -> UUID? {
        if let string = record[newKey] as? String { return UUID(uuidString: string) }
        if let reference = record[oldKey] as? CKRecord.Reference { return UUID(uuidString: reference.recordID.recordName) }
        if let string = record[oldKey] as? String { return UUID(uuidString: string) }
        let unprefixed = oldKey.replacingOccurrences(of: "CD_", with: "")
        if let reference = record[unprefixed] as? CKRecord.Reference { return UUID(uuidString: reference.recordID.recordName) }
        return nil
    }

    /// Applies one fetched batch transactionally. The caller saves tokens only after this succeeds.
    func ingest(records: [CKRecord], deletions: [CKRecord.ID] = []) async throws {
        guard !stopped else { throw CancellationError() }
        // Bound simultaneously loaded asset data on Watch. Completed chunks are safe to replay
        // if a later chunk fails because tokens are not committed until the delegate returns.
        if records.count > 20 {
            try await ingest(records: [], deletions: deletions)
            for offset in stride(from: 0, to: records.count, by: 20) {
                try await ingest(records: Array(records[offset..<min(offset + 20, records.count)]))
            }
            return
        }
        do {
            var images: [CKRecord.ID: Data] = [:]
            for record in records where record.recordType == "CD_Item" {
                let state = try SyncPersistence.state(zone: record.recordID.zoneID.zoneName, record: record.recordID.recordName, context: modelContext)
                if state.deleted || (record.recordChangeTag != nil && state.appliedChangeTag == record.recordChangeTag) { continue }
                let remoteDate = (record["CD_modifiedDate"] as? Date) ?? record.modificationDate ?? Date(timeIntervalSince1970: 0)
                let remoteRevision = record["CD_revision"] as? String ?? ""
                if state.systemFields != nil && !state.pendingSave && state.modifiedDate == remoteDate && state.revision == remoteRevision { continue }
                if state.pendingSave && !SyncPersistence.remoteWins(localDate: state.modifiedDate, localRevision: state.revision, remoteDate: remoteDate, remoteRevision: remoteRevision) { continue }
                if let asset = record["CD_imageAsset"] as? CKAsset {
                    guard let url = asset.fileURL else { throw CloudKitSyncError.invalidData }
                    images[record.recordID] = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                }
            }
            guard !stopped else { throw CancellationError() }
            for record in records where record.recordID.zoneID == markersZoneID {
                guard let zone = record["sourceZone"] as? String, let name = record["sourceRecord"] as? String,
                      [SyncPersistence.itemsZone, SyncPersistence.categoriesZone, SyncPersistence.locationsZone].contains(zone), UUID(uuidString: name) != nil else {
                    throw CloudKitSyncError.invalidData
                }
                try applyDeletion(CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: zone)), markerUploaded: true)
            }
            for id in deletions where id.zoneID != markersZoneID { try applyDeletion(id, markerUploaded: false, recordDeleted: true) }
            for record in records where record.recordID.zoneID != markersZoneID { try apply(record, image: images[record.recordID]) }
            try resolveRelationships()
            if modelContext.hasChanges { try modelContext.save() }
            localChangesCommitted()
        } catch {
            modelContext.rollback()
            needsTokenReset = true
            try? SyncPersistence.checkpoint("needsTokenReset", context: modelContext).completed = true
            try? modelContext.save()
            throw error
        }
    }

    private func apply(_ record: CKRecord, image assetImage: Data?) throws {
        let id = record.recordID
        guard let uuid = UUID(uuidString: id.recordName),
              [itemsZoneID, categoriesZoneID, locationsZoneID].contains(id.zoneID),
              let name = record["CD_name"] as? String else { throw CloudKitSyncError.invalidData }
        let state = try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext)
        if state.deleted {
            transport.removeInventory([.saveRecord(id)])
            if mode == .readWrite && state.markerUploaded {
                state.recordDeleted = false
                transport.queueInventory([.deleteRecord(id)])
            }
            return
        }
        if let tag = record.recordChangeTag, state.appliedChangeTag == tag { return }
        let date = (record["CD_modifiedDate"] as? Date) ?? record.modificationDate ?? Date(timeIntervalSince1970: 0)
        let revision = (record["CD_revision"] as? String) ?? ""
        let hasKnownVersion = state.systemFields != nil || state.pendingSave
        if hasKnownVersion && date == state.modifiedDate && revision == state.revision {
            if state.pendingSave || state.appliedChangeTag != record.recordChangeTag {
                state.systemFields = archive(record)
                state.pendingSave = false
                state.appliedChangeTag = record.recordChangeTag
                transport.removeInventory([.saveRecord(id)])
            }
            return
        }
        let remoteIsNewer = SyncPersistence.remoteWins(localDate: state.modifiedDate, localRevision: state.revision, remoteDate: date, remoteRevision: revision)
        if hasKnownVersion && !remoteIsNewer && (date != state.modifiedDate || revision != state.revision) {
            if state.pendingSave { state.systemFields = archive(record) }
            return
        }
        state.systemFields = archive(record)
        if state.pendingSave && !SyncPersistence.remoteWins(localDate: state.modifiedDate, localRevision: state.revision, remoteDate: date, remoteRevision: revision) {
            // Keep the pending local value, but retry against the newly fetched change tag.
            return
        }
        if id.zoneID == itemsZoneID {
            guard let quantity = record["CD_quantity"] as? Int else { throw CloudKitSyncError.invalidData }
            let image: Data?
            if record["CD_imageAsset"] != nil {
                guard let assetImage else { throw CloudKitSyncError.invalidData }
                image = assetImage
            } else { image = record["CD_imageData"] as? Data }
            let existing = try item(uuid)
            let value = existing ?? Item(uuid, name: name, quantity: quantity)
            if existing == nil { modelContext.insert(value) }
            value.name = name; value.quantity = quantity
            value.sortOrder = record["CD_sortOrder"] as? Int ?? 0
            value.itemCreationDate = record["CD_itemCreationDate"] as? Date ?? record.creationDate ?? date
            value.modifiedDate = date; value.revision = revision
            value.symbol = record["CD_symbol"] as? String
            value.symbolColorData = record["CD_symbolColorData"] as? Data
            value.imageData = image
            state.locationID = referenceID(record, newKey: "CD_locationID", oldKey: "CD_location")
            state.categoryID = referenceID(record, newKey: "CD_categoryID", oldKey: "CD_category")
            value.location = nil; value.category = nil
            state.needsRelationshipResolution = true
        } else if id.zoneID == categoriesZoneID {
            let existing = try category(uuid)
            let value = existing ?? Category(uuid, name: name)
            if existing == nil { modelContext.insert(value) }
            value.name = name; value.sortOrder = record["CD_sortOrder"] as? Int ?? 0
            value.displayInRow = record["CD_displayInRow"] as? Bool ?? true
            value.modifiedDate = date; value.revision = revision
        } else {
            let existing = try location(uuid)
            let value = existing ?? Location(uuid, name: name)
            if existing == nil { modelContext.insert(value) }
            value.name = name; value.sortOrder = record["CD_sortOrder"] as? Int ?? 0
            value.displayInRow = record["CD_displayInRow"] as? Bool ?? true
            value.colorData = record["CD_colorData"] as? Data
            value.modifiedDate = date; value.revision = revision
        }
        state.modifiedDate = date; state.revision = revision
        state.pendingSave = false; state.appliedChangeTag = record.recordChangeTag
        transport.removeInventory([.saveRecord(id)])
    }

    private func applyDeletion(_ id: CKRecord.ID, markerUploaded: Bool, recordDeleted: Bool = false) throws {
        guard let uuid = UUID(uuidString: id.recordName), [itemsZoneID, categoriesZoneID, locationsZoneID].contains(id.zoneID) else { return }
        let state = try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext)
        state.deleted = true; state.pendingSave = false
        state.markerUploaded = state.markerUploaded || markerUploaded
        state.recordDeleted = state.recordDeleted || recordDeleted
        state.locationID = nil; state.categoryID = nil
        transport.removeInventory([.saveRecord(id)])
        if id.zoneID == categoriesZoneID || id.zoneID == locationsZoneID {
            let related = FetchDescriptor<SyncRecordState>(predicate: #Predicate { !$0.deleted && ($0.categoryID == uuid || $0.locationID == uuid) })
            for itemState in try modelContext.fetch(related) {
                if id.zoneID == categoriesZoneID { itemState.categoryID = nil }
                else { itemState.locationID = nil }
            }
        }
        if id.zoneID == itemsZoneID, let value = try item(uuid) { modelContext.delete(value) }
        if id.zoneID == categoriesZoneID, let value = try category(uuid) { modelContext.delete(value) }
        if id.zoneID == locationsZoneID, let value = try location(uuid) { modelContext.delete(value) }
    }

    private func resolveRelationships() throws {
        // Query metadata for unresolved references, not the entire inventory/image store.
        let descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate { !$0.deleted && $0.needsRelationshipResolution })
        for state in try modelContext.fetch(descriptor) where state.zoneName == SyncPersistence.itemsZone {
            guard let uuid = UUID(uuidString: state.recordName), let value = try item(uuid) else { continue }
            var unresolved = false
            if let id = state.locationID {
                let target = try SyncPersistence.state(zone: SyncPersistence.locationsZone, record: id.uuidString, context: modelContext)
                if target.deleted { state.locationID = nil; value.location = nil }
                else if let location = try location(id) { if value.location?.id != id { value.location = location } }
                else { unresolved = true }
            }
            if let id = state.categoryID {
                let target = try SyncPersistence.state(zone: SyncPersistence.categoriesZone, record: id.uuidString, context: modelContext)
                if target.deleted { state.categoryID = nil; value.category = nil }
                else if let category = try category(id) { if value.category?.id != id { value.category = category } }
                else { unresolved = true }
            }
            if state.needsRelationshipResolution != unresolved { state.needsRelationshipResolution = unresolved }
        }
    }

    func acknowledge(_ record: CKRecord) throws {
        if record.recordID.zoneID == markersZoneID {
            guard let zone = record["sourceZone"] as? String, let name = record["sourceRecord"] as? String else { throw CloudKitSyncError.invalidData }
            try SyncPersistence.state(zone: zone, record: name, context: modelContext).markerUploaded = true
        } else {
            let state = try SyncPersistence.state(zone: record.recordID.zoneID.zoneName, record: record.recordID.recordName, context: modelContext)
            state.systemFields = archive(record)
            if !state.deleted, state.revision == (record["CD_revision"] as? String ?? ""),
               state.modifiedDate == (record["CD_modifiedDate"] as? Date) {
                state.pendingSave = false; state.appliedChangeTag = record.recordChangeTag
            }
        }
    }

    private func zoneWasRemoved(_ zoneID: CKRecordZone.ID) throws {
        guard [itemsZoneID, categoriesZoneID, locationsZoneID, markersZoneID].contains(zoneID) else { return }
        try SyncPersistence.checkpoint("removedZone_\(zoneID.zoneName)", context: modelContext).completed = true
        try SyncPersistence.checkpoint("zonesConfirmed", context: modelContext).completed = false
        try modelContext.save()
        throw CloudKitSyncError.zoneRemoved
    }

    private func cleanupAssets(_ ids: [CKRecord.ID]? = nil) {
        for id in ids ?? Array(sentAssets.keys) {
            if let url = sentAssets.removeValue(forKey: id) { try? FileManager.default.removeItem(at: url) }
        }
    }
}

extension CloudKitSyncEngine: CKSyncEngineDelegate {
    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        guard !stopped else { return .init(scope: .zoneIDs([])) }
        if syncEngine === markerEngine {
            switch context.reason {
            case .manual: return .init(scope: .zoneIDs([markersZoneID]))
            default:
                beginAutomaticFetch()
                // Its database subscription covers inventory as well as markers.
                return .init(scope: .all)
            }
        }
        let isManual: Bool
        switch context.reason { case .manual: isManual = true; default: isManual = false }
        guard inventoryCallbackMayProceed(isManual: isManual, sending: false) else { return .init(scope: .zoneIDs([])) }
        return .init(scope: .zoneIDs([itemsZoneID, categoriesZoneID, locationsZoneID]))
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !stopped, mode == .readWrite else { return nil }
        do {
            if syncEngine === inventoryEngine {
                guard try SyncPersistence.checkpoint("bootstrap", context: modelContext).completed else { return nil }
                let isManual: Bool
                switch context.reason { case .manual: isManual = true; default: isManual = false }
                guard inventoryCallbackMayProceed(isManual: isManual, sending: true) else { return nil }
            }
            guard operationError == nil else { return nil }
            let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
            var records: [CKRecord.ID: CKRecord] = [:]
            var changes: [CKSyncEngine.PendingRecordZoneChange] = []
            for change in pending.prefix(50) {
                switch change {
                case .saveRecord(let id):
                    if let record = try await recordForSave(id) { records[id] = record; changes.append(change) }
                    else { syncEngine.state.remove(pendingRecordZoneChanges: [change]) }
                case .deleteRecord(let id):
                    let state = try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext)
                    if state.deleted && state.markerUploaded { changes.append(change) }
                    else { syncEngine.state.remove(pendingRecordZoneChanges: [change]) }
                @unknown default: break
                }
            }
            guard !changes.isEmpty else { return nil }
            let prepared = records
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { prepared[$0] }
        } catch { report(error); return nil }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard !stopped, syncEngine === inventoryEngine || syncEngine === markerEngine else { return }
        do {
            switch event {
            case .accountChange(let change):
                handleAccountChange(change.changeType)
            case .stateUpdate(let update):
                guard operationError == nil else { return }
                let key = syncEngine === markerEngine ? "markerState" : "inventoryState"
                let checkpoint = try SyncPersistence.checkpoint(key, context: modelContext)
                let encoded = try PropertyListEncoder().encode(update.stateSerialization)
                if syncEngine === markerEngine && (automaticFetchInProgress || !stagedRecords.isEmpty || !stagedDeletions.isEmpty) {
                    deferredMarkerState = encoded
                    return
                }
                if checkpoint.data != encoded {
                    checkpoint.data = encoded
                    try modelContext.save()
                }
            case .fetchedRecordZoneChanges(let changes):
                if syncEngine === markerEngine && automaticFetchInProgress {
                    let records = changes.modifications.map(\.record)
                    let deletions = changes.deletions.map(\.recordID)
                    try await ingest(records: records.filter { $0.recordID.zoneID == markersZoneID },
                                     deletions: deletions.filter { $0.zoneID == markersZoneID })
                    stageAutomaticInventory(records: records.filter { $0.recordID.zoneID != markersZoneID },
                                            deletions: deletions.filter { $0.zoneID != markersZoneID })
                } else {
                    try await ingest(records: changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID))
                }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords { try acknowledge(record) }
                for id in changes.deletedRecordIDs {
                    try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext).recordDeleted = true
                }
                for failed in changes.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        if failed.record.recordID.zoneID == markersZoneID {
                            try acknowledge(server)
                            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)])
                        }
                        else { try await ingest(records: [server]) }
                    } else if failed.error.code == .unknownItem {
                        let state = try SyncPersistence.state(zone: failed.record.recordID.zoneID.zoneName, record: failed.record.recordID.recordName, context: modelContext)
                        state.systemFields = nil
                    } else if failed.error.code == .zoneNotFound || failed.error.code == .userDeletedZone {
                        try zoneWasRemoved(failed.record.recordID.zoneID)
                    } else { report(failed.error) }
                }
                for (id, error) in changes.failedRecordDeletes {
                    if error.code == .unknownItem {
                        try SyncPersistence.state(zone: id.zoneID.zoneName, record: id.recordName, context: modelContext).recordDeleted = true
                        syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
                    } else { report(error) }
                }
                try modelContext.save()
                cleanupAssets(changes.savedRecords.map(\.recordID) + changes.deletedRecordIDs)
                localChangesCommitted()
            case .didFetchRecordZoneChanges(let result):
                if let error = result.error, error.code != .operationCancelled {
                    if !(syncEngine === markerEngine && mode == .downloadOnly && error.code == .zoneNotFound) {
                        if error.code == .zoneNotFound || error.code == .userDeletedZone { try zoneWasRemoved(result.zoneID) }
                        report(error)
                    }
                }
            case .fetchedDatabaseChanges(let changes):
                // Do not erase offline work when a zone is removed. Stop uploads and require recovery.
                for deletion in changes.deletions { try zoneWasRemoved(deletion.zoneID) }
            case .sentDatabaseChanges(let result):
                if let error = result.failedZoneSaves.first?.error { report(error) }
                if let error = result.failedZoneDeletes.values.first { report(error) }
            case .didFetchChanges:
                if syncEngine === markerEngine { finishAutomaticFetch() }
            case .didSendChanges:
                if syncEngine === markerEngine { localChangesCommitted() }
            case .willFetchChanges, .willSendChanges, .willFetchRecordZoneChanges:
                break
            @unknown default: break
            }
        } catch {
            modelContext.rollback()
            needsTokenReset = true
            try? SyncPersistence.checkpoint("needsTokenReset", context: modelContext).completed = true
            try? modelContext.save()
            report(error)
        }
    }
}

public enum CloudKitSyncError: LocalizedError {
    case accountNotAvailable, invalidData, syncEngineNotInitialized, zoneRemoved
    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable: return "iCloud is unavailable. Your offline inventory is saved on this device."
        case .invalidData: return "An iCloud record or image could not be read. Try syncing again."
        case .syncEngineNotInitialized: return "Sync is not yet initialized."
        case .zoneRemoved: return "An inventory zone was removed from iCloud. Local inventory has been preserved. Use Repair & Re-sync to recover."
        }
    }
}

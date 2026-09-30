//
//  CloudKitSyncEngine.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/16/25.
//
//  A CloudKit sync engine for managing automatic and manual synchronization of inventory data.
//

import Foundation
import CloudKit
import SwiftData
import SwiftUI
import Combine
import os.log

/// Represents the synchronization state of the CloudKit sync engine
public enum SyncState: Equatable {
    case idle
    case syncing
    case success
    case error(String)
    
    public static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.success, .success):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// A comprehensive CloudKit sync engine that leverages CKSyncEngine for robust synchronization across devices
@MainActor
public class CloudKitSyncEngine: ObservableObject {
    // MARK: - Shared Accessor
    public static weak var shared: CloudKitSyncEngine?
    
    // MARK: - Properties
    @Published public var syncState: SyncState = .idle
    @Published public var lastSyncDate: Date?
    @Published public var isAccountAvailable: Bool = false
    
    var modelContext: ModelContext
    private let container: CKContainer
    private let database: CKDatabase
    private var syncEngine: CKSyncEngine?
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Zone identifiers for different data types
    public let itemsZoneID = CKRecordZone.ID(zoneName: "InventoryItems")
    public let categoriesZoneID = CKRecordZone.ID(zoneName: "InventoryCategories")
    public let locationsZoneID = CKRecordZone.ID(zoneName: "InventoryLocations")
    
    // Logger for debug information
    private let logger = Logger(subsystem: "com.lagera.Inventory", category: "CloudKitSync")
    
    // In-flight task tracking to prevent concurrent cancellation collisions
    private var currentSyncTask: Task<Void, Never>?
    
    // Persistence Keys
    private let tombstoneKey = "CloudKitTombstones_v2"
    private let pendingRelationshipsKey = "CloudKitPendingItemRelationships"
    private let syncEngineStateKey = "CloudKitSyncEngineStateSerialization"
    private let initialUploadKey = "CloudKitInitialUploadDone_v2"
    private let relationshipRepairKey = "CloudKitRelationshipRepair_v2"
    private let tombstoneRetentionDays = 30
    
    // Tombstone entry tracking both recordName and its source zone
    private struct Tombstone: Codable {
        var recordName: String
        var zoneName: String
        var timestamp: Date
    }
    private var tombstones: [String: Tombstone] = [:]
    
    // Pending relationship resolution for items across zone batches
    private struct PendingRefs: Codable {
        var locationID: UUID?
        var categoryID: UUID?
    }
    private var pendingItemRelationships: [UUID: PendingRefs] = [:]
    
    // MARK: - Initialization
    public init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.lagera.Inventory") {
        self.modelContext = modelContext
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        Self.shared = self
        
        loadTombstones()
        loadPendingRelationships()
        
        Task {
            await checkAccountStatus()
            try? await createZonesIfNeeded()
            setupSyncEngine()
            startAutoSync()
            resolvePendingRelationships()
            await repairRelationshipsIfNeeded()
        }
    }
    
    // MARK: - Public / Internal Methods
    
    /// Manually trigger a full sync operation with concurrency de-duplication
    public func manualSync() async {
        guard isAccountAvailable else {
            syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription)
            return
        }
        
        // If a sync is already running, wait for it rather than causing cancellation collisions
        if let existingTask = currentSyncTask {
            _ = await existingTask.value
            return
        }
        
        syncState = .syncing
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.currentSyncTask = nil }
            do {
                try await self.performSync()
                self.syncState = .success
                self.lastSyncDate = Date()
            } catch is CancellationError {
                self.logger.info("Manual sync cancelled")
                self.syncState = .idle
            } catch let ckError as CKError where ckError.code == .operationCancelled {
                self.logger.info("CloudKit operation cancelled")
                self.syncState = .idle
            } catch {
                if (error as NSError).domain == CKErrorDomain && (error as NSError).code == 20 {
                    self.logger.info("CloudKit task cancelled")
                    self.syncState = .idle
                } else {
                    self.logger.error("Manual sync failed: \(error.localizedDescription)")
                    self.syncState = .error(error.localizedDescription)
                }
            }
        }
        
        currentSyncTask = task
        _ = await task.value
    }
    
    /// Forces a complete fresh re-fetch and reconciliation from CloudKit, repairing any missing relationships
    public func forceFullResync() async {
        guard isAccountAvailable else {
            syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription)
            return
        }
        
        if let existingTask = currentSyncTask {
            _ = await existingTask.value
        }
        
        syncState = .syncing
        
        // Reset persisted CKSyncEngine server change tokens
        UserDefaults.standard.removeObject(forKey: syncEngineStateKey)
        setupSyncEngine(stateSerialization: nil)
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.currentSyncTask = nil }
            do {
                try await self.performSync()
                self.syncState = .success
                self.lastSyncDate = Date()
                #if DEBUG
                self.logger.info("Full re-sync completed successfully")
                #endif
            } catch is CancellationError {
                self.syncState = .idle
            } catch let ckError as CKError where ckError.code == .operationCancelled {
                self.syncState = .idle
            } catch {
                if (error as NSError).domain == CKErrorDomain && (error as NSError).code == 20 {
                    self.syncState = .idle
                } else {
                    self.logger.error("Full re-sync failed: \(error.localizedDescription)")
                    self.syncState = .error(error.localizedDescription)
                }
            }
        }
        
        currentSyncTask = task
        _ = await task.value
    }
    
    /// Update the model context (useful when environment changes)
    public func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
    }
    
    /// Add a record ID to the tombstone list and queue deletion in CloudKit
    public func addTombstone(_ recordID: String, zoneName: String = "InventoryItems") {
        let tombstone = Tombstone(recordName: recordID, zoneName: zoneName, timestamp: Date())
        tombstones[recordID] = tombstone
        saveTombstones()
        
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        queueDelete(recordID: recordID, zoneID: zoneID)
        
        Task {
            await cleanupOrphanedData()
        }
    }
    
    /// Queue an Item record to be saved to CloudKit
    func queueSave(for item: Item) {
        let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: itemsZoneID)
        syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }
    
    /// Queue a Category record to be saved to CloudKit
    func queueSave(for category: Category) {
        let recordID = CKRecord.ID(recordName: category.id.uuidString, zoneID: categoriesZoneID)
        syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }
    
    /// Queue a Location record to be saved to CloudKit
    func queueSave(for location: Location) {
        let recordID = CKRecord.ID(recordName: location.id.uuidString, zoneID: locationsZoneID)
        syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }
    
    /// Queue a record deletion in CloudKit
    public func queueDelete(recordID: String, zoneID: CKRecordZone.ID) {
        let ckRecordID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        syncEngine?.state.add(pendingRecordZoneChanges: [.deleteRecord(ckRecordID)])
    }
    
    /// Queue all existing local entities for initial synchronization
    public func queueAllLocalEntities() {
        guard let syncEngine = syncEngine else { return }
        let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let locations = (try? modelContext.fetch(FetchDescriptor<Location>())) ?? []
        
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for item in items {
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: itemsZoneID)
            changes.append(.saveRecord(recordID))
        }
        for category in categories {
            let recordID = CKRecord.ID(recordName: category.id.uuidString, zoneID: categoriesZoneID)
            changes.append(.saveRecord(recordID))
        }
        for location in locations {
            let recordID = CKRecord.ID(recordName: location.id.uuidString, zoneID: locationsZoneID)
            changes.append(.saveRecord(recordID))
        }
        
        if !changes.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: changes)
            #if DEBUG
            logger.info("Queued \(changes.count) existing local entities for upload")
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    /// Check CloudKit account status
    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            isAccountAvailable = status == .available
        } catch {
            isAccountAvailable = false
        }
    }
    
    /// Create the required CloudKit zones if they don't exist
    private func createZonesIfNeeded() async throws {
        let zones = [
            CKRecordZone(zoneID: itemsZoneID),
            CKRecordZone(zoneID: categoriesZoneID),
            CKRecordZone(zoneID: locationsZoneID)
        ]
        
        do {
            _ = try await database.modifyRecordZones(saving: zones, deleting: [])
            #if DEBUG
            logger.info("Successfully created/verified record zones")
            #endif
        } catch let error as CKError {
            if error.code != .zoneNotFound && error.code != .unknownItem && error.code != .serverRecordChanged {
                logger.error("Failed to modify record zones: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    /// Set up the CKSyncEngine with optional restored state serialization
    private func setupSyncEngine(stateSerialization: CKSyncEngine.State.Serialization? = nil) {
        let serializedState: CKSyncEngine.State.Serialization? = {
            if let stateSerialization { return stateSerialization }
            guard let data = UserDefaults.standard.data(forKey: syncEngineStateKey) else { return nil }
            do {
                return try PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            } catch {
                logger.error("Failed to decode CKSyncEngine state: \(error.localizedDescription)")
                return nil
            }
        }()
        
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serializedState,
            delegate: self
        )
        
        syncEngine = CKSyncEngine(configuration)
        #if DEBUG
        logger.info("Initialized sync engine. Resumed from serialization: \(serializedState != nil)")
        #endif
        
        ensureInitialChangesQueuedIfNeeded()
    }
    
    /// Perform a one-time relationship repair re-sync if upgrading from a version with unlinked relationships
    private func repairRelationshipsIfNeeded() async {
        guard isAccountAvailable else { return }
        let alreadyRepaired = UserDefaults.standard.bool(forKey: relationshipRepairKey)
        if !alreadyRepaired {
            UserDefaults.standard.set(true, forKey: relationshipRepairKey)
            logger.info("Executing one-time full re-sync to repair unlinked relationships")
            await forceFullResync()
        }
    }
    
    /// Queues local records for upload if this device has unsynced records
    private func ensureInitialChangesQueuedIfNeeded() {
        if !UserDefaults.standard.bool(forKey: initialUploadKey) {
            queueAllLocalEntities()
            UserDefaults.standard.set(true, forKey: initialUploadKey)
        }
    }
    
    /// Start automatic background synchronization loop
    private func startAutoSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.performAutoSync()
            }
        }
    }
    
    /// Perform automatic sync (less intrusive than manual sync)
    private func performAutoSync() async {
        guard isAccountAvailable && syncState != .syncing && currentSyncTask == nil else { return }
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.currentSyncTask = nil }
            do {
                try await self.performSync()
                self.lastSyncDate = Date()
            } catch is CancellationError {
                // Ignore cancellation
            } catch let ckError as CKError where ckError.code == .operationCancelled {
                // Ignore cancellation
            } catch {
                if (error as NSError).domain != CKErrorDomain || (error as NSError).code != 20 {
                    self.logger.error("Auto-sync failed: \(error.localizedDescription)")
                }
            }
        }
        
        currentSyncTask = task
        _ = await task.value
    }
    
    /// Perform complete fetch and send cycle
    private func performSync() async throws {
        guard let syncEngine = syncEngine else {
            throw CloudKitSyncError.syncEngineNotInitialized
        }
        
        syncState = .syncing
        
        // 1. Fetch changes from CloudKit first
        do {
            try await syncEngine.fetchChanges()
        } catch is CancellationError {
            logger.info("fetchChanges cancelled")
        } catch let error as CKError where error.code == .operationCancelled {
            logger.info("fetchChanges operation cancelled")
        } catch {
            if (error as NSError).domain == CKErrorDomain && (error as NSError).code == 20 {
                logger.info("fetchChanges task cancelled")
            } else {
                throw error
            }
        }
        
        // 2. Send outstanding tombstones to confirm deletions
        try await sendTombstonesToCloudKit()
        
        // 3. Send local changes to CloudKit
        do {
            try await syncEngine.sendChanges()
        } catch is CancellationError {
            logger.info("sendChanges cancelled")
        } catch let error as CKError where error.code == .operationCancelled {
            logger.info("sendChanges operation cancelled")
        } catch {
            if (error as NSError).domain == CKErrorDomain && (error as NSError).code == 20 {
                logger.info("sendChanges task cancelled")
            } else {
                throw error
            }
        }
        
        // 4. Resolve cross-entity relationships
        resolvePendingRelationships()
        saveContext("performSync: final resolve")
    }
    
    /// Send tombstones to CloudKit to confirm deletions across correct zones
    private func sendTombstonesToCloudKit() async throws {
        var tombstonesToRemove: [String] = []
        
        for (recordName, tombstone) in tombstones {
            let zoneID = CKRecordZone.ID(zoneName: tombstone.zoneName)
            let ckRecordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            
            do {
                try await database.deleteRecord(withID: ckRecordID)
                #if DEBUG
                logger.info("Confirmed deletion of record: \(recordName) in zone \(tombstone.zoneName)")
                #endif
                tombstonesToRemove.append(recordName)
            } catch let error as CKError {
                if error.code == .unknownItem {
                    #if DEBUG
                    logger.info("Confirmed deletion of record (already removed in CloudKit): \(recordName)")
                    #endif
                    tombstonesToRemove.append(recordName)
                } else {
                    logger.error("Failed to delete record: \(recordName) - \(error.localizedDescription)")
                }
            } catch {
                logger.error("Unknown error deleting tombstone: \(error.localizedDescription)")
            }
        }
        
        if !tombstonesToRemove.isEmpty {
            for recordID in tombstonesToRemove {
                tombstones.removeValue(forKey: recordID)
            }
            saveTombstones()
        }
    }
    
    // MARK: - Record Conversion Methods
    
    /// Convert an Item to a CKRecord, using CKAsset for large images to avoid the 1 MB record limit
    private func itemToRecord(_ item: Item) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: itemsZoneID)
        let record = CKRecord(recordType: "CD_Item", recordID: recordID)
        
        record["CD_id"] = item.id.uuidString
        record["CD_name"] = item.name
        record["CD_quantity"] = item.quantity
        record["CD_sortOrder"] = item.sortOrder
        record["CD_modifiedDate"] = item.modifiedDate
        record["CD_itemCreationDate"] = item.itemCreationDate
        
        if let symbolColorData = item.symbolColorData {
            record["CD_symbolColorData"] = symbolColorData
        }
        if let symbol = item.symbol {
            record["CD_symbol"] = symbol
        }
        
        // Handle images: Use CKAsset for files > 500KB to prevent CKError.recordSizeExceeded
        if let imageData = item.imageData, !imageData.isEmpty {
            if imageData.count > 500_000 {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitAssets", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempFileURL = tempDir.appendingPathComponent("\(item.id.uuidString).dat")
                
                do {
                    try imageData.write(to: tempFileURL, options: .atomic)
                    record["CD_imageAsset"] = CKAsset(fileURL: tempFileURL)
                    record["CD_imageData"] = nil
                } catch {
                    logger.error("Failed to write image to temp file for CKAsset: \(error.localizedDescription)")
                    record["CD_imageData"] = imageData
                    record["CD_imageAsset"] = nil
                }
            } else {
                record["CD_imageData"] = imageData
                record["CD_imageAsset"] = nil
            }
        } else {
            record["CD_imageData"] = nil
            record["CD_imageAsset"] = nil
        }
        
        // Handle relationships
        if let location = item.location {
            let locationReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: location.id.uuidString, zoneID: locationsZoneID),
                action: .none
            )
            record["CD_location"] = locationReference
        }
        
        if let category = item.category {
            let categoryReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: category.id.uuidString, zoneID: categoriesZoneID),
                action: .none
            )
            record["CD_category"] = categoryReference
        }
        
        return record
    }
    
    /// Convert a Category to a CKRecord
    private func categoryToRecord(_ category: Category) -> CKRecord {
        let recordID = CKRecord.ID(recordName: category.id.uuidString, zoneID: categoriesZoneID)
        let record = CKRecord(recordType: "CD_Category", recordID: recordID)
        
        record["CD_id"] = category.id.uuidString
        record["CD_name"] = category.name
        record["CD_sortOrder"] = category.sortOrder
        record["CD_displayInRow"] = category.displayInRow
        
        return record
    }
    
    /// Convert a Location to a CKRecord
    private func locationToRecord(_ location: Location) -> CKRecord {
        let recordID = CKRecord.ID(recordName: location.id.uuidString, zoneID: locationsZoneID)
        let record = CKRecord(recordType: "CD_Location", recordID: recordID)
        
        record["CD_id"] = location.id.uuidString
        record["CD_name"] = location.name
        record["CD_sortOrder"] = location.sortOrder
        record["CD_displayInRow"] = location.displayInRow
        
        if let colorData = location.colorData {
            record["CD_colorData"] = colorData
        }
        
        return record
    }
    
    /// Ingest an Item from a CKRecord.
    /// Crucially, NEVER blocks or buffers the item if Category/Location are not yet available;
    /// saves the item immediately so images and core fields are never lost on new devices.
    private func recordToItem(_ record: CKRecord) async -> Item? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String,
              let quantity = record["CD_quantity"] as? Int else {
            return nil
        }
        
        // Prevent resurrecting tombstoned items
        if isInTombstones(id.uuidString) {
            logger.info("Ignoring modification for tombstoned item: \(id.uuidString)")
            return nil
        }
        
        // Retrieve image data: check CKAsset first, then fallback to inline data
        var retrievedImageData: Data? = nil
        if let asset = record["CD_imageAsset"] as? CKAsset, let fileURL = asset.fileURL {
            do {
                let assetData = try Data(contentsOf: fileURL)
                if !assetData.isEmpty {
                    retrievedImageData = assetData
                }
            } catch {
                logger.error("Failed to read image data from CKAsset: \(error.localizedDescription)")
            }
        }
        if retrievedImageData == nil, let inlineData = record["CD_imageData"] as? Data {
            retrievedImageData = inlineData
        }
        
        // Parse relationship references
        let targetLocationUUID = extractUUID(from: record["CD_location"] ?? record["location"])
        let targetCategoryUUID = extractUUID(from: record["CD_category"] ?? record["category"])
        
        let item: Item
        if let existingItem = fetchItem(id: id) {
            // Update existing item
            existingItem.name = name
            existingItem.quantity = quantity
            existingItem.modifiedDate = record.modificationDate ?? (record["CD_modifiedDate"] as? Date) ?? Date()
            
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingItem.sortOrder = sortOrder
            }
            if let symbolColorData = record["CD_symbolColorData"] as? Data {
                existingItem.symbolColorData = symbolColorData
            }
            if let symbol = record["CD_symbol"] as? String {
                existingItem.symbol = symbol
            }
            if let retrievedImageData {
                existingItem.imageData = retrievedImageData
            }
            
            item = existingItem
        } else {
            // Create new item immediately so it is available locally
            let newItem = Item(
                id,
                name: name,
                quantity: quantity,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                modifiedDate: record.modificationDate ?? (record["CD_modifiedDate"] as? Date) ?? Date(),
                itemCreationDate: record["CD_itemCreationDate"] as? Date ?? Date()
            )
            
            newItem.symbolColorData = record["CD_symbolColorData"] as? Data
            newItem.symbol = record["CD_symbol"] as? String
            newItem.imageData = retrievedImageData
            
            modelContext.insert(newItem)
            item = newItem
        }
        
        // Resolve or queue Location relationship
        var pendingLocation: UUID? = nil
        if let locUUID = targetLocationUUID {
            if let location = fetchLocation(id: locUUID) {
                item.location = location
            } else {
                pendingLocation = locUUID
            }
        } else if record["CD_location"] == nil && record["location"] == nil {
            item.location = nil
        }
        
        // Resolve or queue Category relationship
        var pendingCategory: UUID? = nil
        if let catUUID = targetCategoryUUID {
            if let category = fetchCategory(id: catUUID) {
                item.category = category
            } else {
                pendingCategory = catUUID
            }
        } else if record["CD_category"] == nil && record["category"] == nil {
            item.category = nil
        }
        
        // Update pending relationships mapping
        if pendingLocation != nil || pendingCategory != nil {
            var existing = pendingItemRelationships[id] ?? PendingRefs(locationID: nil, categoryID: nil)
            if let pendingLocation { existing.locationID = pendingLocation }
            if let pendingCategory { existing.categoryID = pendingCategory }
            pendingItemRelationships[id] = existing
        } else {
            pendingItemRelationships.removeValue(forKey: id)
        }
        
        return item
    }
    
    /// Ingest a Category from a CKRecord and link any pending items
    private func recordToCategory(_ record: CKRecord) async -> Category? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
        if isInTombstones(id.uuidString) {
            logger.info("Ignoring modification for tombstoned category: \(id.uuidString)")
            return nil
        }
        
        let category: Category
        if let existingCategory = fetchCategory(id: id) {
            existingCategory.name = name
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingCategory.sortOrder = sortOrder
            }
            if let displayInRow = record["CD_displayInRow"] as? Bool {
                existingCategory.displayInRow = displayInRow
            }
            category = existingCategory
        } else {
            let newCategory = Category(
                id,
                name: name,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                displayInRow: record["CD_displayInRow"] as? Bool ?? true
            )
            modelContext.insert(newCategory)
            category = newCategory
        }
        
        // Immediately link any items awaiting this category
        resolvePendingCategory(category)
        return category
    }
    
    /// Ingest a Location from a CKRecord and link any pending items
    private func recordToLocation(_ record: CKRecord) async -> Location? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
        if isInTombstones(id.uuidString) {
            logger.info("Ignoring modification for tombstoned location: \(id.uuidString)")
            return nil
        }
        
        let color: Color = {
            if let colorData = record["CD_colorData"] as? Data,
               let decoded = Color(rgbaData: colorData) {
                return decoded
            } else {
                return .white
            }
        }()
        
        let location: Location
        if let existingLocation = fetchLocation(id: id) {
            existingLocation.name = name
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingLocation.sortOrder = sortOrder
            }
            if let displayInRow = record["CD_displayInRow"] as? Bool {
                existingLocation.displayInRow = displayInRow
            }
            if let colorData = record["CD_colorData"] as? Data {
                existingLocation.colorData = colorData
            }
            location = existingLocation
        } else {
            let newLocation = Location(
                id,
                name: name,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                displayInRow: record["CD_displayInRow"] as? Bool ?? true,
                color: color
            )
            modelContext.insert(newLocation)
            location = newLocation
        }
        
        // Immediately link any items awaiting this location
        resolvePendingLocation(location)
        return location
    }
    
    // MARK: - Relationship Resolution Helpers
    
    /// Resolve pending relationships for items waiting for a specific category
    private func resolvePendingCategory(_ category: Category) {
        var didResolveAny = false
        for (itemID, refs) in pendingItemRelationships where refs.categoryID == category.id {
            if let item = fetchItem(id: itemID) {
                item.category = category
                didResolveAny = true
                var updatedRefs = refs
                updatedRefs.categoryID = nil
                if updatedRefs.locationID == nil {
                    pendingItemRelationships.removeValue(forKey: itemID)
                } else {
                    pendingItemRelationships[itemID] = updatedRefs
                }
            }
        }
        if didResolveAny {
            savePendingRelationships()
            saveContext("resolvePendingCategory")
        }
    }
    
    /// Resolve pending relationships for items waiting for a specific location
    private func resolvePendingLocation(_ location: Location) {
        var didResolveAny = false
        for (itemID, refs) in pendingItemRelationships where refs.locationID == location.id {
            if let item = fetchItem(id: itemID) {
                item.location = location
                didResolveAny = true
                var updatedRefs = refs
                updatedRefs.locationID = nil
                if updatedRefs.categoryID == nil {
                    pendingItemRelationships.removeValue(forKey: itemID)
                } else {
                    pendingItemRelationships[itemID] = updatedRefs
                }
            }
        }
        if didResolveAny {
            savePendingRelationships()
            saveContext("resolvePendingLocation")
        }
    }
    
    /// Attempt to resolve any pending item relationships now that more data is present
    private func resolvePendingRelationships() {
        guard !pendingItemRelationships.isEmpty else { return }
        var resolvedIDs: [UUID] = []
        var didModify = false
        
        for (itemID, refs) in pendingItemRelationships {
            guard let item = fetchItem(id: itemID) else {
                // Do NOT discard! Item might be saved or arrived in another batch.
                continue
            }
            
            var updatedRefs = refs
            if let locID = refs.locationID, let location = fetchLocation(id: locID) {
                item.location = location
                updatedRefs.locationID = nil
                didModify = true
            }
            if let catID = refs.categoryID, let category = fetchCategory(id: catID) {
                item.category = category
                updatedRefs.categoryID = nil
                didModify = true
            }
            
            if updatedRefs.locationID == nil && updatedRefs.categoryID == nil {
                resolvedIDs.append(itemID)
            } else {
                pendingItemRelationships[itemID] = updatedRefs
            }
        }
        
        for id in resolvedIDs {
            pendingItemRelationships.removeValue(forKey: id)
        }
        
        if didModify || !resolvedIDs.isEmpty {
            savePendingRelationships()
            saveContext("resolvePendingRelationships")
        }
    }
    
    // MARK: - Small Model Helpers
    
    /// Extract UUID from CKRecord.Reference or String, stripping prefixes if present
    private func extractUUID(from value: Any?) -> UUID? {
        guard let value else { return nil }
        if let ref = value as? CKRecord.Reference {
            let name = ref.recordID.recordName
            if let id = UUID(uuidString: name) { return id }
            let cleaned = name.replacingOccurrences(of: "CD_Location_", with: "")
                              .replacingOccurrences(of: "CD_Category_", with: "")
                              .replacingOccurrences(of: "CD_Item_", with: "")
            return UUID(uuidString: cleaned)
        } else if let str = value as? String {
            if let id = UUID(uuidString: str) { return id }
            let cleaned = str.replacingOccurrences(of: "CD_Location_", with: "")
                             .replacingOccurrences(of: "CD_Category_", with: "")
                             .replacingOccurrences(of: "CD_Item_", with: "")
            return UUID(uuidString: cleaned)
        }
        return nil
    }
    
    /// Safely parse the model UUID from a CKRecord, preferring CD_id and falling back to recordID.recordName
    private func uuid(from record: CKRecord) -> UUID? {
        if let idString = record["CD_id"] as? String, let id = UUID(uuidString: idString) {
            return id
        }
        return UUID(uuidString: record.recordID.recordName)
    }
    
    private func fetchItem(id: UUID) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(descriptor))?.first)
    }
    
    private func fetchCategory(id: UUID) -> Category? {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(descriptor))?.first)
    }
    
    private func fetchLocation(id: UUID) -> Location? {
        let descriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(descriptor))?.first)
    }
    
    /// Delete a local entity by UUID based on the zoneID it belongs to
    private func deleteEntity(for uuid: UUID, zoneID: CKRecordZone.ID) {
        if zoneID == itemsZoneID {
            if let item = fetchItem(id: uuid) { modelContext.delete(item) }
        } else if zoneID == categoriesZoneID {
            if let category = fetchCategory(id: uuid) { modelContext.delete(category) }
        } else if zoneID == locationsZoneID {
            if let location = fetchLocation(id: uuid) { modelContext.delete(location) }
        }
    }
    
    /// Attempt to save the model context and log any errors
    private func saveContext(_ reason: String) {
        do {
            try modelContext.save()
        } catch {
            logger.error("ModelContext save failed (\(reason)): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Duplicate Cleanup
    
    private func cleanupDuplicateItems() {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allItems, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            // Sort to prioritize keeping the item that already has resolved location/category/image
            let sorted = group.sorted { a, b in
                let scoreA = (a.location != nil ? 4 : 0) + (a.category != nil ? 2 : 0) + (a.imageData != nil ? 1 : 0)
                let scoreB = (b.location != nil ? 4 : 0) + (b.category != nil ? 2 : 0) + (b.imageData != nil ? 1 : 0)
                return scoreA > scoreB
            }
            let keeper = sorted[0]
            for duplicate in sorted.dropFirst() {
                if keeper.location == nil, let loc = duplicate.location { keeper.location = loc }
                if keeper.category == nil, let cat = duplicate.category { keeper.category = cat }
                if keeper.imageData == nil, let img = duplicate.imageData { keeper.imageData = img }
                modelContext.delete(duplicate)
            }
        }
    }
    
    private func cleanupDuplicateCategories() {
        let descriptor = FetchDescriptor<Category>()
        guard let allCategories = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allCategories, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
    }
    
    private func cleanupDuplicateLocations() {
        let descriptor = FetchDescriptor<Location>()
        guard let allLocations = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allLocations, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
    }
    
    // MARK: - State & Tombstone Persistence
    
    private func loadTombstones() {
        if let savedData = UserDefaults.standard.data(forKey: tombstoneKey),
           let savedTombstones = try? JSONDecoder().decode([String: Tombstone].self, from: savedData) {
            self.tombstones = savedTombstones
            purgeTombstones()
        }
    }
    
    private func saveTombstones() {
        if let encodedData = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(encodedData, forKey: tombstoneKey)
        }
    }
    
    private func isInTombstones(_ recordID: String) -> Bool {
        return tombstones[recordID] != nil
    }
    
    private func purgeTombstones() {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -tombstoneRetentionDays, to: Date()) else { return }
        tombstones = tombstones.filter { $0.value.timestamp > cutoffDate }
        saveTombstones()
    }
    
    private func loadPendingRelationships() {
        guard let savedData = UserDefaults.standard.data(forKey: pendingRelationshipsKey) else { return }
        if let dict = try? JSONDecoder().decode([String: PendingRefs].self, from: savedData) {
            var loaded: [UUID: PendingRefs] = [:]
            for (key, refs) in dict {
                if let uuid = UUID(uuidString: key) {
                    loaded[uuid] = refs
                }
            }
            self.pendingItemRelationships = loaded
        } else if let savedPending = try? JSONDecoder().decode([UUID: PendingRefs].self, from: savedData) {
            self.pendingItemRelationships = savedPending
        }
    }
    
    private func savePendingRelationships() {
        var dict: [String: PendingRefs] = [:]
        for (uuid, refs) in pendingItemRelationships {
            dict[uuid.uuidString] = refs
        }
        if let encodedData = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(encodedData, forKey: pendingRelationshipsKey)
        }
    }
    
    nonisolated private func cleanUpTempAssetFiles() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitAssets", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    /// Comprehensive cleanup of orphaned relationships and invalid data
    private func cleanupOrphanedData() async {
        guard isAccountAvailable && lastSyncDate != nil else { return }
        
        let itemDescriptor = FetchDescriptor<Item>()
        if let items = try? modelContext.fetch(itemDescriptor) {
            for item in items where isInTombstones(item.id.uuidString) {
                logger.info("Removing tombstoned item: \(item.id)")
                modelContext.delete(item)
            }
        }
        
        saveContext("cleanupOrphanedData")
        cleanupDuplicateItems()
        cleanupDuplicateCategories()
        cleanupDuplicateLocations()
    }
    
    deinit {
        syncTimer?.invalidate()
        cleanUpTempAssetFiles()
    }
}

// MARK: - CKSyncEngine Delegate

extension CloudKitSyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        #if DEBUG
        logger.debug("Handling event: \(String(describing: event))")
        #endif
        
        switch event {
        case .accountChange(let accountEvent):
            switch accountEvent.changeType {
            case .signIn(_):
                isAccountAvailable = true
            case .signOut(_):
                isAccountAvailable = false
            case .switchAccounts(_, _):
                isAccountAvailable = true
            @unknown default:
                break
            }
            
        case .stateUpdate(let stateEvent):
            // Persist the state serialization so CKSyncEngine can resume with correct tokens on next launch
            do {
                let serializedData = try PropertyListEncoder().encode(stateEvent.stateSerialization)
                UserDefaults.standard.set(serializedData, forKey: syncEngineStateKey)
                #if DEBUG
                logger.debug("Saved CKSyncEngine state serialization (\(serializedData.count) bytes)")
                #endif
            } catch {
                logger.error("Failed to encode CKSyncEngine state: \(error.localizedDescription)")
            }
            
        case .fetchedRecordZoneChanges(let changes):
            // 1. Ingest Categories and Locations FIRST so Items can immediately link them
            let categoriesAndLocations = changes.modifications.filter { $0.record.recordType != "CD_Item" }
            let itemModifications = changes.modifications.filter { $0.record.recordType == "CD_Item" }
            
            for modification in categoriesAndLocations {
                let record = modification.record
                switch record.recordType {
                case "CD_Category":
                    _ = await recordToCategory(record)
                case "CD_Location":
                    _ = await recordToLocation(record)
                default:
                    logger.warning("Unknown record type: \(record.recordType)")
                }
            }
            
            // Persist newly ingested categories and locations so fetchDescriptor can see them
            saveContext("afterIngestingCategoriesAndLocations")
            
            // 2. Ingest Items now that related entities are present and saved in context
            for modification in itemModifications {
                _ = await recordToItem(modification.record)
            }
            
            // Persist newly ingested items before resolving cross-zone relationships
            saveContext("afterIngestingItems")
            
            // 3. Process deletions
            for deletion in changes.deletions {
                let recordID = deletion.recordID
                let recordName = recordID.recordName
                let zoneName = recordID.zoneID.zoneName
                
                let tombstone = Tombstone(recordName: recordName, zoneName: zoneName, timestamp: Date())
                tombstones[recordName] = tombstone
                saveTombstones()
                
                if let uuid = UUID(uuidString: recordName) {
                    pendingItemRelationships.removeValue(forKey: uuid)
                    deleteEntity(for: uuid, zoneID: recordID.zoneID)
                }
            }
            
            // 4. Resolve any remaining cross-zone relationships
            resolvePendingRelationships()
            
            // 5. Clean up duplicates and save
            cleanupDuplicateItems()
            cleanupDuplicateCategories()
            cleanupDuplicateLocations()
            savePendingRelationships()
            saveContext("fetchedRecordZoneChanges")
            
        case .sentRecordZoneChanges(let changes):
            logger.info("Sent \(changes.savedRecords.count) records to CloudKit")
            for failedSave in changes.failedRecordSaves {
                logger.error("Failed to save record: \(failedSave.record.recordID) - \(failedSave.error.localizedDescription)")
            }
            cleanUpTempAssetFiles()
            
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                logger.info("Zone deleted: \(deletion.zoneID)")
                if deletion.zoneID == itemsZoneID {
                    let descriptor = FetchDescriptor<Item>()
                    if let items = try? modelContext.fetch(descriptor) {
                        items.forEach { modelContext.delete($0) }
                    }
                } else if deletion.zoneID == categoriesZoneID {
                    let descriptor = FetchDescriptor<Category>()
                    if let categories = try? modelContext.fetch(descriptor) {
                        categories.forEach { modelContext.delete($0) }
                    }
                } else if deletion.zoneID == locationsZoneID {
                    let descriptor = FetchDescriptor<Location>()
                    if let locations = try? modelContext.fetch(descriptor) {
                        locations.forEach { modelContext.delete($0) }
                    }
                }
            }
            if !changes.deletions.isEmpty {
                saveContext("fetchedDatabaseChanges: zone deletions")
            }
            
        case .willFetchChanges, .didFetchChanges, .willSendChanges,
             .didSendChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .sentDatabaseChanges:
            break
            
        @unknown default:
            logger.warning("Unknown event type: \(event)")
        }
    }
    
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter { change in
            context.options.scope.contains(change)
        }
        guard !pendingChanges.isEmpty else {
            return nil
        }
        
        let batch = Array(pendingChanges.prefix(100))
        
        #if DEBUG
        logger.info("Preparing next record change batch with \(batch.count) changes")
        #endif
        
        // Build the records dictionary on the main actor before entering the escaping closure
        var mutableRecordsToSave: [CKRecord.ID: CKRecord] = [:]
        for change in batch {
            switch change {
            case .saveRecord(let recordID):
                if let record = self.record(for: recordID) {
                    mutableRecordsToSave[recordID] = record
                }
            case .deleteRecord:
                break
            @unknown default:
                break
            }
        }
        let recordsToSave = mutableRecordsToSave
        
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { recordID in
            return recordsToSave[recordID]
        }
    }
    
    /// Resolve the CKRecord for a given recordID to send in a change batch
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return nil }
        
        if recordID.zoneID == itemsZoneID {
            if let item = fetchItem(id: uuid) {
                return itemToRecord(item)
            }
        } else if recordID.zoneID == categoriesZoneID {
            if let category = fetchCategory(id: uuid) {
                return categoryToRecord(category)
            }
        } else if recordID.zoneID == locationsZoneID {
            if let location = fetchLocation(id: uuid) {
                return locationToRecord(location)
            }
        }
        return nil
    }
}

// MARK: - Error Types

public enum CloudKitSyncError: LocalizedError {
    case accountNotAvailable
    case syncInProgress
    case recordNotFound
    case invalidData
    case syncEngineNotInitialized
    
    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable:
            return "iCloud account is not available"
        case .syncInProgress:
            return "Synchronization is already in progress"
        case .recordNotFound:
            return "Data not found in iCloud"
        case .invalidData:
            return "Invalid data encountered"
        case .syncEngineNotInitialized:
            return "Syncing is not yet initialized"
        }
    }
}

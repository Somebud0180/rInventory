//
//  WatchCloudKitSyncEngine.swift
//  rInventory Watch
//
//  Created by GitHub Copilot on 9/28/25.
//
//  A simplified CloudKit sync engine for Apple Watch that only fetches data (read-only).

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

/// A simplified CloudKit sync engine for Apple Watch that only fetches changes from CloudKit
@MainActor
public class CloudKitSyncEngine: ObservableObject {
    // MARK: - Properties
    @Published public var syncState: SyncState = .idle
    @Published public var lastSyncDate: Date?
    @Published public var isAccountAvailable: Bool = false
    
    var modelContext: ModelContext
    private let container: CKContainer
    private let database: CKDatabase
    private var syncEngine: CKSyncEngine?
    private var syncTimer: Timer?
    
    // Zone identifiers for different data types
    private let itemsZoneID = CKRecordZone.ID(zoneName: "InventoryItems")
    private let categoriesZoneID = CKRecordZone.ID(zoneName: "InventoryCategories")
    private let locationsZoneID = CKRecordZone.ID(zoneName: "InventoryLocations")
    
    // Logger for debug information
    private let logger = Logger(subsystem: "com.lagera.Inventory", category: "CloudKitSync")
    
    // Pending relationship resolution for items across zone batches
    private struct PendingRefs {
        var locationID: UUID?
        var categoryID: UUID?
    }
    private var pendingItemRelationships: [UUID: PendingRefs] = [:]
    
    // MARK: - Initialization
    public init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.lagera.Inventory") {
        self.modelContext = modelContext
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        
        Task {
            await checkAccountStatus()
            setupSyncEngine()
            startAutoSync()
        }
    }
    
    // MARK: - Public Methods
    
    /// Manually trigger a sync operation
    public func manualSync() async {
        guard isAccountAvailable else {
            syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription)
            return
        }
        
        syncState = .syncing
        
        do {
            try await performSync()
            syncState = .success
            lastSyncDate = Date()
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }
    
    /// Update the model context (useful when environment changes)
    public func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
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
    
    /// Set up the CKSyncEngine
    private func setupSyncEngine() {
        // Create a configuration for the sync engine
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: nil,
            delegate: self
        )
        
        syncEngine = CKSyncEngine(configuration)
        logger.info("Initialized sync engine")
    }
    
    /// Start automatic synchronization (using a longer interval for Watch to save battery)
    private func startAutoSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.performAutoSync()
            }
        }
    }
    
    /// Perform automatic sync (less intrusive than manual sync)
    private func performAutoSync() async {
        guard isAccountAvailable && syncState != .syncing else { return }
        
        do {
            try await performSync()
            lastSyncDate = Date()
        } catch {
            // Silent failure for auto-sync
            logger.error("Auto-sync failed: \(error.localizedDescription)")
        }
    }
    
    /// Perform sync operation (fetch only, no sending changes)
    private func performSync() async throws {
        guard let syncEngine = syncEngine else {
            throw CloudKitSyncError.syncEngineNotInitialized
        }
        
        syncState = .syncing
        
        // Only fetch changes from CloudKit (watch is read-only)
        try await syncEngine.fetchChanges()
        
        // Final pass to resolve any pending relationships after all batches
        resolvePendingRelationships()
        saveContext("performSync: final resolve")
        
        syncState = .success
        lastSyncDate = Date()
    }
    
    // MARK: - Record Conversion Methods
    
    /// Create an Item from a CKRecord
    private func recordToItem(_ record: CKRecord) async -> Item? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String,
              let quantity = record["CD_quantity"] as? Int else {
            return nil
        }
        
        // Stash desired relationships for later resolution
        updatePendingRelationships(from: record)
        
        // Check if item exists locally
        if let existingItem = fetchItem(id: id) {
            // Update existing item
            existingItem.name = name
            existingItem.quantity = quantity
            existingItem.modifiedDate = record.modificationDate ?? Date()
            
            // Update other fields
            if let symbolColorData = record["CD_symbolColorData"] as? Data {
                existingItem.symbolColorData = symbolColorData
            }
            if let symbol = record["CD_symbol"] as? String {
                existingItem.symbol = symbol
            }
            if let imageData = record["CD_imageData"] as? Data {
                existingItem.imageData = imageData
            }
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingItem.sortOrder = sortOrder
            }
            
            // Handle relationships (only set if found; don't overwrite with nil)
            if let locationReference = record["CD_location"] as? CKRecord.Reference,
               let uuid = UUID(uuidString: locationReference.recordID.recordName),
               let location = fetchLocation(id: uuid) {
                existingItem.location = location
            }
            if let categoryReference = record["CD_category"] as? CKRecord.Reference,
               let uuid = UUID(uuidString: categoryReference.recordID.recordName),
               let category = fetchCategory(id: uuid) {
                existingItem.category = category
            }
            
            return existingItem
        } else {
            // Create new item
            let newItem = Item(
                id,
                name: name,
                quantity: quantity,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                modifiedDate: record.modificationDate ?? Date(),
                itemCreationDate: record["CD_itemCreationDate"] as? Date ?? Date()
            )
            
            // Set optional fields
            if let symbolColorData = record["CD_symbolColorData"] as? Data {
                newItem.symbolColorData = symbolColorData
            }
            if let symbol = record["CD_symbol"] as? String {
                newItem.symbol = symbol
            }
            if let imageData = record["CD_imageData"] as? Data {
                newItem.imageData = imageData
            }
            
            // Relationships will be resolved later (after all entities are present)
            modelContext.insert(newItem)
            return newItem
        }
    }
    
    /// Create a Category from a CKRecord
    private func recordToCategory(_ record: CKRecord) async -> Category? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
        if let existingCategory = fetchCategory(id: id) {
            existingCategory.name = name
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingCategory.sortOrder = sortOrder
            }
            if let displayInRow = record["CD_displayInRow"] as? Bool {
                existingCategory.displayInRow = displayInRow
            }
            return existingCategory
        } else {
            let newCategory = Category(
                id,
                name: name,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                displayInRow: record["CD_displayInRow"] as? Bool ?? true
            )
            modelContext.insert(newCategory)
            return newCategory
        }
    }
    
    /// Create a Location from a CKRecord
    private func recordToLocation(_ record: CKRecord) async -> Location? {
        guard let id = uuid(from: record),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
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
            return existingLocation
        } else {
            let color: Color = {
                if let colorData = record["CD_colorData"] as? Data,
                   let decoded = Color(rgbaData: colorData) {
                    return decoded
                } else {
                    return .white
                }
            }()
            
            let newLocation = Location(
                id,
                name: name,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                displayInRow: record["CD_displayInRow"] as? Bool ?? true,
                color: color
            )
            modelContext.insert(newLocation)
            return newLocation
        }
    }
    
    /// Process relationships after all entities are created/updated
    private func processRelationships(for items: [Item], with records: [CKRecord]) {
        for (item, record) in zip(items, records) {
            if let locationReference = record["CD_location"] as? CKRecord.Reference {
                let locationId = locationReference.recordID.recordName
                if let uuid = UUID(uuidString: locationId) {
                    let locationDescriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == uuid })
                    if let location = ((try? modelContext.fetch(locationDescriptor))?.first) {
                        item.location = location
                    }
                }
            }
            
            if let categoryReference = record["CD_category"] as? CKRecord.Reference {
                let categoryId = categoryReference.recordID.recordName
                if let uuid = UUID(uuidString: categoryId) {
                    let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == uuid })
                    if let category = ((try? modelContext.fetch(categoryDescriptor))?.first) {
                        item.category = category
                    }
                }
            }
        }
    }
    
    /// Extract and store desired relationships from an item record for later resolution
    private func updatePendingRelationships(from record: CKRecord) {
        guard record.recordType == "CD_Item" else { return }
        // Prefer CD_id, fall back to recordID.recordName for robustness
        let itemID: UUID? = {
            if let idString = record["CD_id"] as? String, let id = UUID(uuidString: idString) { return id }
            return UUID(uuidString: record.recordID.recordName)
        }()
        guard let itemID else { return }
        let locID: UUID? = (record["CD_location"] as? CKRecord.Reference).flatMap { UUID(uuidString: $0.recordID.recordName) }
        let catID: UUID? = (record["CD_category"] as? CKRecord.Reference).flatMap { UUID(uuidString: $0.recordID.recordName) }
        let existing = pendingItemRelationships[itemID] ?? PendingRefs(locationID: nil, categoryID: nil)
        pendingItemRelationships[itemID] = PendingRefs(
            locationID: locID ?? existing.locationID,
            categoryID: catID ?? existing.categoryID
        )
    }
    
    // MARK: - Small Helpers
    /// Safely parse the model UUID from a CKRecord, preferring CD_id and falling back to recordID.recordName
    private func uuid(from record: CKRecord) -> UUID? {
        if let idString = record["CD_id"] as? String, let id = UUID(uuidString: idString) {
            return id
        }
        return UUID(uuidString: record.recordID.recordName)
    }
    
    private func fetchItem(id: UUID) -> Item? {
        let d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(d))?.first)
    }
    
    private func fetchCategory(id: UUID) -> Category? {
        let d = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(d))?.first)
    }
    
    private func fetchLocation(id: UUID) -> Location? {
        let d = FetchDescriptor<Location>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(d))?.first)
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
        do { try modelContext.save() } catch {
            logger.error("ModelContext save failed (\(reason)): \(error.localizedDescription)")
        }
    }
    
    /// Attempt to resolve any pending item relationships now that more data may be present
    private func resolvePendingRelationships() {
        guard !pendingItemRelationships.isEmpty else { return }
        var resolvedIDs: [UUID] = []
        for (itemID, refs) in pendingItemRelationships {
            let itemDescriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            guard let item = ((try? modelContext.fetch(itemDescriptor))?.first) else { continue }
            var resolvedAll = true
            if let locID = refs.locationID {
                let locationDescriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == locID })
                if let location = ((try? modelContext.fetch(locationDescriptor))?.first) {
                    item.location = location
                } else {
                    resolvedAll = false
                }
            }
            if let catID = refs.categoryID {
                let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == catID })
                if let category = ((try? modelContext.fetch(categoryDescriptor))?.first) {
                    item.category = category
                } else {
                    resolvedAll = false
                }
            }
            if resolvedAll { resolvedIDs.append(itemID) }
        }
        // Remove fully-resolved entries
        for id in resolvedIDs { pendingItemRelationships.removeValue(forKey: id) }
        // Save if we made any changes
        if !resolvedIDs.isEmpty { saveContext("resolvePendingRelationships") }
    }
    
    deinit {
        syncTimer?.invalidate()
    }
}

// MARK: - CKSyncEngine Delegate

extension CloudKitSyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        logger.debug("Handling event: \(String(describing: event))")
        
        switch event {
        case .accountChange(let event):
            switch event.changeType {
            case .signIn(_):
                isAccountAvailable = true
            case .signOut(_):
                isAccountAvailable = false
            case .switchAccounts(_, _):
                isAccountAvailable = true
            @unknown default:
                break
            }
            
        case .fetchedRecordZoneChanges(let changes):
            // Process record changes from CloudKit
            var itemsToProcess = [Item]()
            var itemRecords = [CKRecord]()
            
            // Process modifications
            for modification in changes.modifications {
                let record = modification.record
                switch record.recordType {
                case "CD_Item":
                    if let item = await recordToItem(record) {
                        itemsToProcess.append(item)
                        itemRecords.append(record)
                    }
                case "CD_Category":
                    _ = await recordToCategory(record)
                    // After categories arrive, try resolving pending relationships
                    resolvePendingRelationships()
                case "CD_Location":
                    _ = await recordToLocation(record)
                    // After locations arrive, try resolving pending relationships
                    resolvePendingRelationships()
                default:
                    logger.warning("Unknown record type: \(record.recordType)")
                }
            }
            
            // Process deletions
            for deletion in changes.deletions {
                let recordID = deletion.recordID
                if let uuid = UUID(uuidString: recordID.recordName) {
                    // Clear any pending relationships for deleted items
                    pendingItemRelationships.removeValue(forKey: uuid)
                    
                    // Delete the entity locally
                    deleteEntity(for: uuid, zoneID: recordID.zoneID)
                }
            }
            
            // Process relationships for items in this batch immediately when possible
            if !itemsToProcess.isEmpty && !itemRecords.isEmpty {
                processRelationships(for: itemsToProcess, with: itemRecords)
            }
            
            // Attempt to resolve any cross-zone pending relationships
            resolvePendingRelationships()
            
            saveContext("fetchedRecordZoneChanges")
            
        case .fetchedDatabaseChanges(let changes):
            // Handle database level changes (e.g., deleted zones)
            for deletion in changes.deletions {
                logger.info("Zone deleted: \(deletion.zoneID)")
                
                // If a zone was deleted, we should clear all data in that zone
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
            
        case .stateUpdate, .willFetchChanges, .didFetchChanges, .willSendChanges,
                .didSendChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
                .sentDatabaseChanges, .sentRecordZoneChanges:
            // These events are informational and don't require specific handling
            break
            
        @unknown default:
            logger.warning("Unknown event type: \(event)")
        }
    }
    
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // For read-only Watch app, we don't need to send any changes to CloudKit
        // Return an empty batch to satisfy the protocol
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: [CKSyncEngine.PendingRecordZoneChange]()) { _ in
            return nil // No records to send back to CloudKit
        }
    }
}

// MARK: - Error Types

public enum CloudKitSyncError: LocalizedError {
    case accountNotAvailable
    case syncInProgress
    case syncEngineNotInitialized
    
    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable:
            return "iCloud account is not available"
        case .syncInProgress:
            return "Synchronization is already in progress"
        case .syncEngineNotInitialized:
            return "Sync engine not initialized"
        }
    }
}

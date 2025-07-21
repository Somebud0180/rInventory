//
//  CloudKitSyncEngine.swift
//  rInventory
//
//  Created by GitHub Copilot on 7/16/25.
//
//  A CloudKit sync engine for managing automatic and manual synchronization of inventory data.

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

/// A comprehensive CloudKit sync engine that leverages CKSyncEngine for efficient synchronization
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
    private var cancellables = Set<AnyCancellable>()
    
    // Zone identifiers for different data types
    private let itemsZoneID = CKRecordZone.ID(zoneName: "InventoryItems")
    private let categoriesZoneID = CKRecordZone.ID(zoneName: "InventoryCategories")
    private let locationsZoneID = CKRecordZone.ID(zoneName: "InventoryLocations")
    
    // Logger for debug information
    private let logger = Logger(subsystem: "com.lagera.Inventory", category: "CloudKitSync")
    
    // MARK: - Initialization
    public init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.lagera.Inventory") {
        self.modelContext = modelContext
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        
        Task {
            await checkAccountStatus()
            try? await createZonesIfNeeded()
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
    
    /// Create the required CloudKit zones if they don't exist
    private func createZonesIfNeeded() async throws {
        // Create record zones if they don't exist
        let zones = [
            CKRecordZone(zoneID: itemsZoneID),
            CKRecordZone(zoneID: categoriesZoneID),
            CKRecordZone(zoneID: locationsZoneID)
        ]
        
        do {
            _ = try await database.modifyRecordZones(saving: zones, deleting: [])
            logger.info("Successfully created/verified record zones")
        } catch let error as CKError {
            // Only throw if it's not a zone already exists error
            if error.code != .zoneNotFound && error.code != .unknownItem {
                throw error
            }
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
    
    /// Start automatic synchronization
    private func startAutoSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
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
    
    /// Perform complete sync operation
    private func performSync() async throws {
        guard let syncEngine = syncEngine else {
            throw CloudKitSyncError.syncEngineNotInitialized
        }
        
        syncState = .syncing
        
        // First fetch changes from CloudKit
        try await syncEngine.fetchChanges()
        
        // Then send any local changes to CloudKit
        try await syncEngine.sendChanges()
        
        syncState = .success
        lastSyncDate = Date()
    }
    
    // MARK: - Record Conversion Methods
    
    /// Convert an Item to a CKRecord
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
        if let imageData = item.imageData {
            record["CD_imageData"] = imageData
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
    
    /// Create an Item from a CKRecord
    private func recordToItem(_ record: CKRecord) async -> Item? {
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String,
              let quantity = record["CD_quantity"] as? Int else {
            return nil
        }
        
        // Check if item exists locally
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []
        
        if let existingItem = existingItems.first {
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
            
            // Handle relationships
            if let locationReference = record["CD_location"] as? CKRecord.Reference {
                let locationId = locationReference.recordID.recordName
                if let uuid = UUID(uuidString: locationId) {
                    let locationDescriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == uuid })
                    let locations = (try? modelContext.fetch(locationDescriptor)) ?? []
                    existingItem.location = locations.first
                }
            }
            
            if let categoryReference = record["CD_category"] as? CKRecord.Reference {
                let categoryId = categoryReference.recordID.recordName
                if let uuid = UUID(uuidString: categoryId) {
                    let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == uuid })
                    let categories = (try? modelContext.fetch(categoryDescriptor)) ?? []
                    existingItem.category = categories.first
                }
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
            
            // Handle relationships - do this after inserting all entities
            
            modelContext.insert(newItem)
            return newItem
        }
    }
    
    /// Create a Category from a CKRecord
    private func recordToCategory(_ record: CKRecord) async -> Category? {
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        let existingCategories = (try? modelContext.fetch(descriptor)) ?? []
        
        if let existingCategory = existingCategories.first {
            // Update existing category
            existingCategory.name = name
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingCategory.sortOrder = sortOrder
            }
            if let displayInRow = record["CD_displayInRow"] as? Bool {
                existingCategory.displayInRow = displayInRow
            }
            return existingCategory
        } else {
            // Create new category
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
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String else {
            return nil
        }
        
        let descriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == id })
        let existingLocations = (try? modelContext.fetch(descriptor)) ?? []
        
        if let existingLocation = existingLocations.first {
            // Update existing location
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
            // Create new location
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
                    if let location = try? modelContext.fetch(locationDescriptor).first {
                        item.location = location
                    }
                }
            }
            
            if let categoryReference = record["CD_category"] as? CKRecord.Reference {
                let categoryId = categoryReference.recordID.recordName
                if let uuid = UUID(uuidString: categoryId) {
                    let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == uuid })
                    if let category = try? modelContext.fetch(categoryDescriptor).first {
                        item.category = category
                    }
                }
            }
        }
    }
    
    /// Clean up duplicate items with the same ID
    private func cleanupDuplicateItems() {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allItems, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let winner = group.first!
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
        try? modelContext.save()
    }
    
    /// Clean up duplicate categories with the same ID
    private func cleanupDuplicateCategories() {
        let descriptor = FetchDescriptor<Category>()
        guard let allCategories = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allCategories, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let winner = group.first!
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
        try? modelContext.save()
    }
    
    /// Clean up duplicate locations with the same ID
    private func cleanupDuplicateLocations() {
        let descriptor = FetchDescriptor<Location>()
        guard let allLocations = try? modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allLocations, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let winner = group.first!
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
        try? modelContext.save()
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
                case "CD_Location":
                    _ = await recordToLocation(record)
                default:
                    logger.warning("Unknown record type: \(record.recordType)")
                }
            }
            
            // Process deletions
            for deletion in changes.deletions {
                let recordID = deletion.recordID
                let recordName = recordID.recordName
                
                if let uuid = UUID(uuidString: recordName) {
                    if recordID.zoneID == itemsZoneID {
                        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == uuid })
                        if let items = try? modelContext.fetch(descriptor), let item = items.first {
                            modelContext.delete(item)
                        }
                    } else if recordID.zoneID == categoriesZoneID {
                        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == uuid })
                        if let categories = try? modelContext.fetch(descriptor), let category = categories.first {
                            modelContext.delete(category)
                        }
                    } else if recordID.zoneID == locationsZoneID {
                        let descriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == uuid })
                        if let locations = try? modelContext.fetch(descriptor), let location = locations.first {
                            modelContext.delete(location)
                        }
                    }
                }
            }
            
            // Process relationships for items
            if !itemsToProcess.isEmpty && !itemRecords.isEmpty {
                processRelationships(for: itemsToProcess, with: itemRecords)
            }
            
            // Clean up any duplicates
            cleanupDuplicateItems()
            cleanupDuplicateCategories()
            cleanupDuplicateLocations()
            
            try? modelContext.save()
            
        case .sentRecordZoneChanges(let changes):
            // Log the results of sending records to CloudKit
            logger.info("Sent \(changes.savedRecords.count) records to CloudKit")
            
            for failedSave in changes.failedRecordSaves {
                logger.error("Failed to save record: \(failedSave.record.recordID) - \(failedSave.error.localizedDescription)")
            }
            
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
                try? modelContext.save()
            }
            
        case .stateUpdate, .willFetchChanges, .didFetchChanges, .willSendChanges,
                .didSendChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
                .sentDatabaseChanges:
            // These events are informational and don't require specific handling
            break
            
        @unknown default:
            logger.warning("Unknown event type: \(event)")
        }
    }
    
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        logger.info("Preparing next record change batch")
        
        // Fetch all entities from the model context
        let itemDescriptor = FetchDescriptor<Item>()
        let categoryDescriptor = FetchDescriptor<Category>()
        let locationDescriptor = FetchDescriptor<Location>()
        
        let items = (try? modelContext.fetch(itemDescriptor)) ?? []
        let categories = (try? modelContext.fetch(categoryDescriptor)) ?? []
        let locations = (try? modelContext.fetch(locationDescriptor)) ?? []
        
        // Generate records for all entities
        let itemRecords = items.map { self.itemToRecord($0) }
        let categoryRecords = categories.map { self.categoryToRecord($0) }
        let locationRecords = locations.map { self.locationToRecord($0) }
        
        // Combine all records
        let allRecords = itemRecords + categoryRecords + locationRecords
        
        // Create a record map for the batch
        var recordMap: [CKRecord.ID: CKRecord] = [:]
        for record in allRecords {
            recordMap[record.recordID] = record
        }
        
        // Create batch with the pendingChanges parameter as suggested by the compiler
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: [CKSyncEngine.PendingRecordZoneChange]()) { recordID in
            return recordMap[recordID]
        }
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
            return "Record not found in CloudKit"
        case .invalidData:
            return "Invalid data format"
        case .syncEngineNotInitialized:
            return "Sync engine not initialized"
        }
    }
}

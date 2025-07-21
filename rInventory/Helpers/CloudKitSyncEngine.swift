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

/// A comprehensive CloudKit sync engine that handles both automatic and manual synchronization
@MainActor
public class CloudKitSyncEngine: ObservableObject {
    // MARK: - Properties
    @Published public var syncState: SyncState = .idle
    @Published public var lastSyncDate: Date?
    @Published public var isAccountAvailable: Bool = false
    
    private let container: CKContainer
    private let database: CKDatabase
    private var _modelContext: ModelContext
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Public accessor for model context
    public var modelContext: ModelContext {
        return _modelContext
    }
    
    // Record zones for different data types
    private let itemsZone = CKRecordZone(zoneName: "InventoryItems")
    private let categoriesZone = CKRecordZone(zoneName: "InventoryCategories")
    private let locationsZone = CKRecordZone(zoneName: "InventoryLocations")
    
    // MARK: - Initialization
    public init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.lagera.Inventory") {
        self._modelContext = modelContext
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        
        Task {
            await checkAccountStatus()
            await setupRecordZones()
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
    
    /// Force a refresh by fetching changes from CloudKit
    public func refreshFromCloud() async {
        guard isAccountAvailable else {
            syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription)
            return
        }
        
        syncState = .syncing
        
        do {
            try await fetchChanges()
            syncState = .success
            lastSyncDate = Date()
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }
    
    /// Send local changes to CloudKit
    public func sendChangesToCloud() async {
        guard isAccountAvailable else {
            syncState = .error(CloudKitSyncError.accountNotAvailable.localizedDescription)
            return
        }
        
        syncState = .syncing
        
        do {
            try await sendChanges()
            syncState = .success
            lastSyncDate = Date()
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }
    
    /// Update the model context (useful when environment changes)
    public func updateModelContext(_ newContext: ModelContext) {
        _modelContext = newContext
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
    
    /// Set up CloudKit record zones
    private func setupRecordZones() async {
        guard isAccountAvailable else { return }
        
        let zones = [itemsZone, categoriesZone, locationsZone]
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: zones, recordZoneIDsToDelete: nil)
        
        database.add(operation)
    }
    
    /// Start automatic synchronization
    private func startAutoSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
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
            print("Auto-sync failed: \(error)")
        }
    }
    
    /// Perform complete sync operation
    private func performSync() async throws {
        try await fetchChanges()
        try await sendChanges()
    }
    
    /// Fetch changes from CloudKit and update local data
    public func fetchChanges() async throws {
        // Fetch Items
        try await fetchItems()
        
        // Fetch Categories
        try await fetchCategories()
        
        // Fetch Locations
        try await fetchLocations()
    }
    
    /// Send local changes to CloudKit
    public func sendChanges() async throws {
        // Send Items
        try await sendItems()
        
        // Send Categories
        try await sendCategories()
        
        // Send Locations
        try await sendLocations()
    }
    
    // MARK: - Items Sync
    
    private func fetchItems() async throws {
        let query = CKQuery(recordType: "CD_Item", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.zoneID = itemsZone.zoneID
        
        var fetchedRecords: [CKRecord] = []
        
        return try await withCheckedThrowingContinuation { continuation in
            operation.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    fetchedRecords.append(record)
                case .failure(let error):
                    print("Error fetching item record: \(error)")
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    Task {
                        await self.processItemRecords(fetchedRecords)
                        continuation.resume()
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            self.database.add(operation)
        }
    }
    
    private func processItemRecords(_ records: [CKRecord]) async {
        for record in records {
            await processItemRecord(record)
        }
        cleanupDuplicateItems()
    }
    
    private func processItemRecord(_ record: CKRecord) async {
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String,
              let quantity = record["CD_quantity"] as? Int else {
            return
        }
        
        // Check if item exists locally
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        let existingItems = (try? _modelContext.fetch(descriptor)) ?? []
        
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
            
            _modelContext.insert(newItem)
        }
        
        try? _modelContext.save()
    }
    
    private func sendItems() async throws {
        let descriptor = FetchDescriptor<Item>()
        let items = try _modelContext.fetch(descriptor)
        
        var recordsToSave: [CKRecord] = []
        
        for item in items {
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: itemsZone.zoneID)
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
            
            recordsToSave.append(record)
        }
        
        if !recordsToSave.isEmpty {
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave)
            operation.savePolicy = .changedKeys
            
            database.add(operation)
        }
    }
    
    private func cleanupDuplicateItems() {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? _modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allItems, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let _winner = group.first!
            for duplicate in group.dropFirst() {
                _modelContext.delete(duplicate)
            }
        }
        try? _modelContext.save()
    }
    
    // MARK: - Categories Sync
    
    private func fetchCategories() async throws {
        // When querying for a specific Category by id, use NSPredicate(format: "id == %@", uuid.uuidString).
        // Do NOT use predicates on recordName for querying.
        let query = CKQuery(recordType: "CD_Category", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.zoneID = categoriesZone.zoneID
        
        var fetchedRecords: [CKRecord] = []
        
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
            case .failure(let error):
                print("Error fetching category record: \(error)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                Task {
                    await self.processCategoryRecords(fetchedRecords)
                }
            case .failure(let error):
                print("Query failed: \(error)")
            }
        }
        
        database.add(operation)
    }
    
    private func processCategoryRecords(_ records: [CKRecord]) async {
        // Process all records without saving individual changes
        var categoriesToUpdate: [Category] = []
        var categoriesToInsert: [Category] = []
        
        for record in records {
            if let processedCategory = await processCategoryRecord(record, saveImmediately: false) {
                // Check if this category already exists in the context
                let categoryId = processedCategory.id
                let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryId })
                let existingCount = (try? _modelContext.fetchCount(descriptor)) ?? 0
                
                if existingCount > 0 {
                    categoriesToUpdate.append(processedCategory)
                } else {
                    categoriesToInsert.append(processedCategory)
                }
            }
        }
        
        // Perform deduplication on the batch before saving anything
        await deduplicateAndSaveCategories(toUpdate: categoriesToUpdate, toInsert: categoriesToInsert)
    }
    
    private func processCategoryRecord(_ record: CKRecord, saveImmediately: Bool = true) async -> Category? {
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String else { return nil }
        
        // When querying for a specific Category by id, use NSPredicate(format: "id == %@", uuid.uuidString).
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        let existingCategories = (try? _modelContext.fetch(descriptor)) ?? []
        if let existingCategory = existingCategories.first {
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingCategory.sortOrder = sortOrder
            }
            existingCategory.name = name
            return existingCategory
        } else {
            let newCategory = Category(
                id,
                name: name,
                sortOrder: record["CD_sortOrder"] as? Int ?? 0,
                displayInRow: record["CD_displayInRow"] as? Bool ?? true
            )
            if !saveImmediately {
                return newCategory
            } else {
                _modelContext.insert(newCategory)
                try? _modelContext.save()
                return newCategory
            }
        }
    }
    
    /// Deduplicate and save categories in a single transaction
    private func deduplicateAndSaveCategories(toUpdate: [Category], toInsert: [Category]) async {
        // For insertions, check for duplicates by ID
        var validInsertions: [Category] = []
        let existingIds = Set((try? _modelContext.fetch(FetchDescriptor<Category>())) ?? []).map { $0.id }
        
        // Group new categories by ID to handle duplicates in the batch itself
        let groupedInsertions = Dictionary(grouping: toInsert, by: { $0.id })
        
        for (id, categories) in groupedInsertions {
            // Skip if category with this ID already exists in context
            guard !existingIds.contains(id) else { continue }
            
            // If multiple categories with same ID in this batch, take the first one
            if let categoryToInsert = categories.first {
                validInsertions.append(categoryToInsert)
            }
        }
        
        // Insert only the deduplicated categories
        for category in validInsertions {
            _modelContext.insert(category)
        }
        
        // Save everything in one transaction
        do {
            try _modelContext.save()
        } catch {
            print("Error saving deduplicated categories: \(error)")
        }
        
        // Clean up any remaining duplicates (safety net)
        cleanupDuplicateCategories()
    }
    
    private func sendCategories() async throws {
        let descriptor = FetchDescriptor<Category>()
        let categories = try _modelContext.fetch(descriptor)
        
        var recordsToSave: [CKRecord] = []
        
        for category in categories {
            let recordID = CKRecord.ID(recordName: category.id.uuidString, zoneID: categoriesZone.zoneID)
            let record = CKRecord(recordType: "CD_Category", recordID: recordID)
            
            record["CD_id"] = category.id.uuidString
            record["CD_name"] = category.name
            record["CD_sortOrder"] = category.sortOrder
            record["CD_displayInRow"] = category.displayInRow
            
            recordsToSave.append(record)
        }
        
        if !recordsToSave.isEmpty {
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave)
            operation.savePolicy = .changedKeys
            
            database.add(operation)
        }
    }
    
    // MARK: - Locations Sync
    
    private func fetchLocations() async throws {
        // When querying for a specific Location by id, use NSPredicate(format: "id == %@", uuid.uuidString).
        // Do NOT use predicates on recordName for querying.
        let query = CKQuery(recordType: "CD_Location", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.zoneID = locationsZone.zoneID
        
        var fetchedRecords: [CKRecord] = []
        
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
            case .failure(let error):
                print("Error fetching location record: \(error)")
            }
        }
        
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                Task {
                    await self.processLocationRecords(fetchedRecords)
                }
            case .failure(let error):
                print("Query failed: \(error)")
            }
        }
        
        database.add(operation)
    }
    
    private func processLocationRecords(_ records: [CKRecord]) async {
        // Process all records without saving individual changes
        var locationsToUpdate: [Location] = []
        var locationsToInsert: [Location] = []
        
        for record in records {
            if let processedLocation = await processLocationRecord(record, saveImmediately: false) {
                // Check if this location already exists in the context
                let locationId = processedLocation.id
                let descriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == locationId })
                let existingCount = (try? _modelContext.fetchCount(descriptor)) ?? 0
                
                if existingCount > 0 {
                    locationsToUpdate.append(processedLocation)
                } else {
                    locationsToInsert.append(processedLocation)
                }
            }
        }
        
        // Perform deduplication on the batch before saving anything
        await deduplicateAndSaveLocations(toUpdate: locationsToUpdate, toInsert: locationsToInsert)
    }
    
    private func processLocationRecord(_ record: CKRecord, saveImmediately: Bool = true) async -> Location? {
        guard let idString = record["CD_id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["CD_name"] as? String else { return nil }
        
        // When querying for a specific Location by id, use NSPredicate(format: "id == %@", uuid.uuidString).
        let descriptor = FetchDescriptor<Location>(predicate: #Predicate { $0.id == id })
        let existingLocations = (try? _modelContext.fetch(descriptor)) ?? []
        if let existingLocation = existingLocations.first {
            if let sortOrder = record["CD_sortOrder"] as? Int {
                existingLocation.sortOrder = sortOrder
            }
            if let colorData = record["CD_colorData"] as? Data {
                existingLocation.colorData = colorData
            }
            existingLocation.name = name
            return existingLocation
        } else {
            let color: Color =
            {
                if let colorData = record["CD_colorData"] as? Data, let decoded = Color(rgbaData: colorData) {
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
            
            if !saveImmediately {
                return newLocation
            } else {
                _modelContext.insert(newLocation)
                try? _modelContext.save()
                return newLocation
            }
        }
    }
    
    /// Deduplicate and save locations in a single transaction
    private func deduplicateAndSaveLocations(toUpdate: [Location], toInsert: [Location]) async {
        // For insertions, check for duplicates by ID
        var validInsertions: [Location] = []
        let existingIds = Set((try? _modelContext.fetch(FetchDescriptor<Location>())) ?? []).map { $0.id }
        
        // Group new locations by ID to handle duplicates in the batch itself
        let groupedInsertions = Dictionary(grouping: toInsert, by: { $0.id })
        
        for (id, locations) in groupedInsertions {
            // Skip if location with this ID already exists in context
            guard !existingIds.contains(id) else { continue }
            
            // If multiple locations with same ID in this batch, take the first one
            if let locationToInsert = locations.first {
                validInsertions.append(locationToInsert)
            }
        }
        
        // Insert only the deduplicated locations
        for location in validInsertions {
            _modelContext.insert(location)
        }
        
        // Save everything in one transaction
        do {
            try _modelContext.save()
        } catch {
            print("Error saving deduplicated locations: \(error)")
        }
        
        // Clean up any remaining duplicates (safety net)
        cleanupDuplicateLocations()
    }
    
    private func sendLocations() async throws {
        let descriptor = FetchDescriptor<Location>()
        let locations = try _modelContext.fetch(descriptor)
        
        var recordsToSave: [CKRecord] = []
        
        for location in locations {
            let recordID = CKRecord.ID(recordName: location.id.uuidString, zoneID: locationsZone.zoneID)
            let record = CKRecord(recordType: "CD_Location", recordID: recordID)
            
            record["CD_id"] = location.id.uuidString
            record["CD_name"] = location.name
            record["CD_sortOrder"] = location.sortOrder
            record["CD_displayInRow"] = location.displayInRow
            
            if let colorData = location.colorData {
                record["CD_colorData"] = colorData
            }
            
            recordsToSave.append(record)
        }
        
        if !recordsToSave.isEmpty {
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave)
            operation.savePolicy = .changedKeys
            
            database.add(operation)
        }
    }
    
    /// Remove duplicate Category objects with the same id, keeping the first and merging if needed
    private func cleanupDuplicateCategories() {
        let descriptor = FetchDescriptor<Category>()
        guard let allCategories = try? _modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allCategories, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let _winner = group.first!
            for duplicate in group.dropFirst() {
                _modelContext.delete(duplicate)
            }
        }
        try? _modelContext.save()
    }
    
    /// Remove duplicate Location objects with the same id, keeping the first and merging if needed
    private func cleanupDuplicateLocations() {
        let descriptor = FetchDescriptor<Location>()
        guard let allLocations = try? _modelContext.fetch(descriptor) else { return }
        let grouped = Dictionary(grouping: allLocations, by: { $0.id })
        for (_, group) in grouped where group.count > 1 {
            let _winner = group.first!
            for duplicate in group.dropFirst() {
                _modelContext.delete(duplicate)
            }
        }
        try? _modelContext.save()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
}

// MARK: - Error Types

public enum CloudKitSyncError: LocalizedError {
    case accountNotAvailable
    case syncInProgress
    case recordNotFound
    case invalidData
    
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
        }
    }
}


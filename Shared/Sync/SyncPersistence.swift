import Foundation
import SwiftData

/// Local-only metadata and outbox. Inventory and pending work commit in one store transaction.
@Model
final class SyncRecordState {
    @Attribute(.unique) var key: String = ""
    var zoneName: String = ""
    var recordName: String = ""
    var pendingSave: Bool = false
    var revision: String = ""
    var modifiedDate: Date = Date(timeIntervalSince1970: 0)
    var systemFields: Data?
    var deleted: Bool = false
    var markerUploaded: Bool = false
    var recordDeleted: Bool = false
    var locationID: UUID?
    var categoryID: UUID?
    var needsRelationshipResolution: Bool = false
    var appliedChangeTag: String?

    init(zone: String, record: String) {
        zoneName = zone
        recordName = record
        key = Self.key(zone: zone, record: record)
    }

    static func key(zone: String, record: String) -> String { "\(zone)|\(record)" }
}

@Model
final class SyncCheckpoint {
    @Attribute(.unique) var key: String = ""
    var data: Data?
    var completed: Bool = false
    init(_ key: String) { self.key = key }
}

@MainActor
enum SyncPersistence {
    nonisolated static let itemsZone = "InventoryItems"
    nonisolated static let categoriesZone = "InventoryCategories"
    nonisolated static let locationsZone = "InventoryLocations"
    nonisolated static let markersZone = "InventoryDeletionMarkers"
    static let schema = Schema([Item.self, Category.self, Location.self, SyncRecordState.self, SyncCheckpoint.self])

    static func state(zone: String, record: String, context: ModelContext) throws -> SyncRecordState {
        let key = SyncRecordState.key(zone: zone, record: record)
        var descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let state = try context.fetch(descriptor).first { return state }
        let state = SyncRecordState(zone: zone, record: record)
        context.insert(state)
        return state
    }

    static func checkpoint(_ key: String, context: ModelContext) throws -> SyncCheckpoint {
        var descriptor = FetchDescriptor<SyncCheckpoint>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let entry = try context.fetch(descriptor).first { return entry }
        let entry = SyncCheckpoint(key)
        context.insert(entry)
        return entry
    }

    static func remoteWins(localDate: Date, localRevision: String, remoteDate: Date, remoteRevision: String) -> Bool {
        remoteDate > localDate || (remoteDate == localDate && remoteRevision > localRevision)
    }

    /// Use this at user mutation boundaries, never while applying remote records.
    static func save(_ context: ModelContext, commit: ((ModelContext) throws -> Void)? = nil) throws {
        do {
            let deleted = context.deletedModelsArray
            let deletedIDs = Set(deleted.map(\.persistentModelID))
            let changed = context.insertedModelsArray + context.changedModelsArray
            var visited = Set<PersistentIdentifier>()
            for model in changed where !deletedIDs.contains(model.persistentModelID) && visited.insert(model.persistentModelID).inserted {
                let identity: (String, UUID)?
                switch model {
                case let item as Item: identity = (itemsZone, item.id)
                case let category as Category: identity = (categoriesZone, category.id)
                case let location as Location: identity = (locationsZone, location.id)
                default: identity = nil
                }
                guard let (zone, id) = identity else { continue }
                let state = try state(zone: zone, record: id.uuidString, context: context)
                // A deleted UUID is never reused.
                guard !state.deleted else { context.delete(model); continue }
                let date = Date()
                let revision = UUID().uuidString
                switch model {
                case let item as Item:
                    item.modifiedDate = date; item.revision = revision
                    state.locationID = item.location?.id; state.categoryID = item.category?.id
                    state.needsRelationshipResolution = false
                case let category as Category: category.modifiedDate = date; category.revision = revision
                case let location as Location: location.modifiedDate = date; location.revision = revision
                default: break
                }
                state.modifiedDate = date
                state.revision = revision
                state.pendingSave = true
            }
            for model in deleted {
                let identity: (String, UUID)?
                switch model {
                case let item as Item: identity = (itemsZone, item.id)
                case let category as Category: identity = (categoriesZone, category.id)
                case let location as Location: identity = (locationsZone, location.id)
                default: identity = nil
                }
                if let (zone, id) = identity {
                    let state = try state(zone: zone, record: id.uuidString, context: context)
                    state.deleted = true; state.pendingSave = false
                    state.markerUploaded = false; state.recordDeleted = false
                    state.locationID = nil; state.categoryID = nil
                }
            }
            if let commit { try commit(context) } else { try context.save() }
            if CloudKitSyncEngine.shared?.modelContext === context {
                CloudKitSyncEngine.shared?.localChangesCommitted()
            }
        } catch {
            context.rollback()
            CloudKitSyncEngine.shared?.report(error)
            throw error
        }
    }

    static func saveReporting(_ context: ModelContext) {
        do { try save(context) } catch { /* save() reports and restores the last committed state */ }
    }
}

import Foundation
import SwiftData
import CloudKit
import CryptoKit
import Combine

@MainActor
protocol InventoryAccountProvider {
    func identity() async throws -> String?
}

struct CloudKitAccountProvider: InventoryAccountProvider {
    private var container: CKContainer { CKContainer(identifier: "iCloud.com.lagera.Inventory") }
    func identity() async throws -> String? {
        switch try await container.accountStatus() {
        case .available: return try await container.userRecordID().recordName
        case .noAccount: return nil
        default: throw CloudKitSyncError.accountNotAvailable
        }
    }
}

private struct OfflineAccountProvider: InventoryAccountProvider {
    func identity() async throws -> String? { nil }
}

/// Owns the context and engine as a unit. A verified account never receives another account's work.
@MainActor
final class InventoryStoreCoordinator: ObservableObject {
    static let shared: InventoryStoreCoordinator = {
        // Hosted unit tests exercise their injected transports, not a real signed-in account.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        return InventoryStoreCoordinator(accountProvider: testing ? OfflineAccountProvider() : nil)
    }()
    @Published private(set) var container: ModelContainer
    @Published private(set) var engine: CloudKitSyncEngine
    @Published private(set) var storeKey: String
    @Published private(set) var hasOfflineInventory = false
    @Published private(set) var errorMessage: String?
    private let directory: URL
    private let defaults: UserDefaults
    private let accountProvider: any InventoryAccountProvider
    private let mode: CloudKitSyncEngine.Mode
    private let transportFactory: (@MainActor () -> any InventorySyncTransport)?
    private var accountObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?

    init(directory: URL? = nil, defaults: UserDefaults = .standard,
         accountProvider: (any InventoryAccountProvider)? = nil,
         transportFactory: (@MainActor () -> any InventorySyncTransport)? = nil,
         mode: CloudKitSyncEngine.Mode? = nil) {
        let root = directory ?? Self.storeDirectory()
        self.directory = root; self.defaults = defaults; self.accountProvider = accountProvider ?? CloudKitAccountProvider()
        self.transportFactory = transportFactory
        #if os(watchOS)
        self.mode = mode ?? .downloadOnly
        #else
        self.mode = mode ?? .readWrite
        #endif
        let key = defaults.string(forKey: "InventoryLastStore_v3") ?? "offline"
        storeKey = key
        let initialContainer: ModelContainer
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let path = defaults.string(forKey: "InventoryStorePath_v3_\(key)") ?? "\(key).store"
            initialContainer = try Self.open(root.appendingPathComponent(path))
        } catch { fatalError("Could not open inventory store: \(error)") }
        initialContainer.mainContext.autosaveEnabled = false
        container = initialContainer
        engine = CloudKitSyncEngine(modelContext: initialContainer.mainContext, mode: self.mode, transport: transportFactory?())
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task.detached { await self?.accountChanged() }
        }
        configureAccountCallback()
    }

    static func accountKey(_ identity: String) -> String {
        "account-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func storeDirectory() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.lagera.Inventory")
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("rInventory", isDirectory: true)
    }
    private static func open(_ url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: SyncPersistence.schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: SyncPersistence.schema, configurations: [configuration])
    }
    private func configureAccountCallback() {
        engine.accountDidChange = { [weak self] in Task.detached { await self?.accountChanged() } }
    }
    private func accountChanged() async {
        // A delegate detecting a real identity change has already invalidated the engine.
        // Quiesce that work before checking the replacement account. Notifications alone
        // are hints; verifying the same account must not cancel its sync.
        if engine.stopped { await engine.stop() }
        await refreshAccount(force: true)
        // A real delegate account change may have stopped the engine while an earlier
        // verification was in flight. Recheck once after that coalesced refresh ends.
        if engine.stopped { await refreshAccount(force: true) }
    }

    /// Coalesces launch/foreground refreshes and verifies identity before starting CloudKit work.
    func refreshAccount(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 5 { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil; self.lastRefresh = Date() }
            do {
                let identity = try await self.accountProvider.identity()
                let key = identity.map(Self.accountKey) ?? "offline"
                // Always quiesce the old engine before replacing its context.
                if key != self.storeKey {
                    await self.engine.stop()
                    let container = try self.containerForKey(key, verified: identity != nil)
                    container.mainContext.autosaveEnabled = false
                    self.container = container
                    self.storeKey = key
                    self.engine = CloudKitSyncEngine(modelContext: container.mainContext, mode: self.mode, transport: self.transportFactory?())
                    self.configureAccountCallback()
                } else if self.engine.stopped {
                    await self.engine.stop()
                    self.engine = CloudKitSyncEngine(modelContext: self.container.mainContext, mode: self.mode, transport: self.transportFactory?())
                    self.configureAccountCallback()
                }
                self.defaults.set(key, forKey: "InventoryLastStore_v3")
                #if os(watchOS)
                WatchVisibilityPreferences.shared.activate(accountKey: key, context: self.container.mainContext)
                #endif
                if identity != nil {
                    try self.engine.start(accountIdentity: identity)
                    await self.engine.manualSync()
                }
                self.errorMessage = nil
                try self.updateOfflineAvailability()
            } catch {
                // A temporarily unavailable identity does not reassign cached inventory to another account.
                await self.engine.stop()
                self.engine = CloudKitSyncEngine(modelContext: self.container.mainContext, mode: self.mode, transport: self.transportFactory?())
                self.configureAccountCallback()
                self.errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }

    private func containerForKey(_ key: String, verified: Bool) throws -> ModelContainer {
        if let filename = defaults.string(forKey: "InventoryStorePath_v3_\(key)") {
            return try Self.open(directory.appendingPathComponent(filename))
        }
        let legacy = directory.appendingPathComponent("rInventory.store")
        let adoptLegacy = verified && defaults.string(forKey: "InventoryLegacyOwner_v3") == nil && FileManager.default.fileExists(atPath: legacy.path)
        let filename = adoptLegacy ? "rInventory.store" : "\(key).store"
        let container = try Self.open(directory.appendingPathComponent(filename))
        if adoptLegacy {
            try adoptLegacyDefaults(context: container.mainContext)
            defaults.set(key, forKey: "InventoryLegacyOwner_v3")
        }
        defaults.set(filename, forKey: "InventoryStorePath_v3_\(key)")
        return container
    }

    private struct LegacyTombstone: Decodable { let recordName: String; let zoneName: String; let timestamp: Date }
    private struct LegacyRefs: Decodable { let locationID: UUID?; let categoryID: UUID? }
    private func adoptLegacyDefaults(context: ModelContext) throws {
        let migrated = try SyncPersistence.checkpoint("legacyDefaults", context: context)
        guard !migrated.completed else { return }
        if let data = defaults.data(forKey: "CloudKitTombstones_v2") {
            let tombstones = try JSONDecoder().decode([String: LegacyTombstone].self, from: data)
            for tombstone in tombstones.values {
                let state = try SyncPersistence.state(zone: tombstone.zoneName, record: tombstone.recordName, context: context)
                state.deleted = true; state.pendingSave = false
            }
        }
        if let data = defaults.data(forKey: "CloudKitPendingItemRelationships"),
           let refs = try? JSONDecoder().decode([String: LegacyRefs].self, from: data) {
            for (id, refs) in refs {
                let state = try SyncPersistence.state(zone: SyncPersistence.itemsZone, record: id, context: context)
                state.locationID = refs.locationID; state.categoryID = refs.categoryID
                state.needsRelationshipResolution = true
            }
        }
        // Intentionally discard old tokens so deletion markers and all remote entities are fetched.
        migrated.completed = true
        try context.save()
    }

    private func updateOfflineAvailability() throws {
        guard mode == .readWrite, storeKey != "offline" else { hasOfflineInventory = false; return }
        let url = directory.appendingPathComponent("offline.store")
        guard FileManager.default.fileExists(atPath: url.path) else { hasOfflineInventory = false; return }
        let offline = try Self.open(url)
        let items = try offline.mainContext.fetch(FetchDescriptor<Item>())
        hasOfflineInventory = try items.contains { item in
            !(try SyncPersistence.checkpoint("offline-import-\(item.id)", context: container.mainContext)).completed
        }
    }

    /// Explicit import; provenance prevents duplicate imports and the offline originals are preserved.
    func importOfflineInventory() throws {
        guard mode == .readWrite, storeKey != "offline", engine.isAccountAvailable else { throw CloudKitSyncError.accountNotAvailable }
        let offline = try Self.open(directory.appendingPathComponent("offline.store"))
        let target = container.mainContext
        do {
            var locations: [UUID: Location] = [:]
            var categories: [UUID: Category] = [:]
            for item in try offline.mainContext.fetch(FetchDescriptor<Item>()) {
                let provenance = try SyncPersistence.checkpoint("offline-import-\(item.id)", context: target)
                guard !provenance.completed else { continue }
                var location: Location?
                if let source = item.location {
                    let mapping = try SyncPersistence.checkpoint("offline-location-\(source.id)", context: target)
                    if let cached = locations[source.id] { location = cached }
                    else if let data = mapping.data, let string = String(data: data, encoding: .utf8), let id = UUID(uuidString: string) {
                        location = try target.fetch(FetchDescriptor<Location>(predicate: #Predicate { $0.id == id })).first
                    }
                    if location == nil {
                        let copy = Location(name: source.name, sortOrder: source.sortOrder, displayInRow: source.displayInRow, color: source.color)
                        target.insert(copy); location = copy; mapping.data = Data(copy.id.uuidString.utf8)
                    }
                    locations[source.id] = location
                }
                var category: Category?
                if let source = item.category {
                    let mapping = try SyncPersistence.checkpoint("offline-category-\(source.id)", context: target)
                    if let cached = categories[source.id] { category = cached }
                    else if let data = mapping.data, let string = String(data: data, encoding: .utf8), let id = UUID(uuidString: string) {
                        category = try target.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first
                    }
                    if category == nil {
                        let copy = Category(name: source.name, sortOrder: source.sortOrder, displayInRow: source.displayInRow)
                        target.insert(copy); category = copy; mapping.data = Data(copy.id.uuidString.utf8)
                    }
                    categories[source.id] = category
                }
                let copy = Item(name: item.name, quantity: item.quantity, location: location, category: category, imageData: item.imageData,
                                symbol: item.symbol, symbolColor: item.symbolColor, sortOrder: item.sortOrder, itemCreationDate: item.itemCreationDate)
                target.insert(copy)
                provenance.completed = true
            }
            try SyncPersistence.save(target)
            try updateOfflineAvailability()
        } catch { target.rollback(); errorMessage = error.localizedDescription; throw error }
    }
}

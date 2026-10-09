import Testing
import SwiftData
import UIKit
@testable import rInventory

@MainActor
struct InventoryIntentTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: SyncPersistence.schema, configurations: [
            ModelConfiguration(schema: SyncPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    @Test func exactNamesExcludeOtherProductsButIncludeEveryLocation() throws {
        let store = try container()
        let context = store.mainContext
        context.insert(Item(name: "Cable", quantity: 2, location: Location(name: "Desk")))
        context.insert(Item(name: "CABLE", quantity: 3, location: Location(name: "Drawer")))
        context.insert(Item(name: "Cable organizer", quantity: 10))
        let matches = try InventoryIntentSearch.matches("  cable \n", context: context)
        #expect(matches.count == 2)
        #expect(matches.reduce(0) { $0 + $1.quantity } == 5)
        let response = InventoryIntentSearch.summary(matches, query: "cable")
        #expect(response.contains("Desk"))
        #expect(response.contains("Drawer"))
    }

    @Test func partialSearchAndMissingLocation() throws {
        let store = try container()
        store.mainContext.insert(Item(name: "Batteries", quantity: 0))
        let matches = try InventoryIntentSearch.matches("batt", context: store.mainContext)
        #expect(matches.count == 1)
        let response = InventoryIntentSearch.summary(matches, query: "batt")
        #expect(!response.contains("quantity"))
        #expect(response.contains("no location set"))
        #expect(try InventoryIntentSearch.matches("   ", context: store.mainContext).isEmpty)
        #expect(try InventoryIntentSearch.matches("missing", context: store.mainContext).isEmpty)
    }

    @Test func spokenResultsAreBoundedAndReportRemainingMatches() {
        let items = (1...7).map { Item(name: "Item \($0)", quantity: 1) }
        let response = InventoryIntentSearch.summary(items, query: "Item")
        #expect(response.contains("2 more matching entries"))
        #expect(!response.contains("Item 6:"))
        #expect(InventoryIntentSearch.summary([], query: "Keys").contains("couldn't find Keys"))
    }

    @Test func misspellingsSuggestNamesWithoutCountingThem() throws {
        let store = try container()
        store.mainContext.insert(Item(name: "Apple Pencil", quantity: 2))
        store.mainContext.insert(Item(name: "Apple Pencil", quantity: 3))
        store.mainContext.insert(Item(name: "Apple Pencil Pro", quantity: 1))
        #expect(try InventoryIntentSearch.matches("Apple Pencle", context: store.mainContext).isEmpty)
        #expect(try InventoryIntentSearch.suggestions("Apple Pencle", context: store.mainContext) == ["Apple Pencil", "Apple Pencil Pro"])
        let response = try InventoryIntentSearch.noMatchResponse("Apple Pencle", context: store.mainContext)
        #expect(response.contains("Similarly named items"))
        #expect(!response.contains("quantity"))
        #expect(try InventoryIntentSearch.suggestions("Refrigerator", context: store.mainContext).isEmpty)
        #expect(try InventoryIntentSearch.suggestions("Pen", context: store.mainContext).isEmpty)
    }

    @Test func spellingSuggestionsNormalizeAccentsAndStayBounded() throws {
        let store = try container()
        for name in ["Café Mug", "Cafe Rug", "Cafe Jug", "Cafe Bug"] {
            store.mainContext.insert(Item(name: name, quantity: 1))
        }
        let suggestions = try InventoryIntentSearch.suggestions("CAFE MUGG", context: store.mainContext)
        #expect(suggestions.first == "Café Mug")
        #expect(suggestions.count == 3)
    }

    @Test func homeActionOnlyHandlesKnownShortcuts() {
        let router = InventoryActionRouter()
        #expect(!router.handle(UIApplicationShortcutItem(type: "unknown", localizedTitle: "Unknown")))
        #expect(!router.newItemRequested)
        #expect(router.handle(UIApplicationShortcutItem(type: InventoryActionRouter.addItemShortcutType, localizedTitle: "Add new item")))
        #expect(router.newItemRequested)
    }
}

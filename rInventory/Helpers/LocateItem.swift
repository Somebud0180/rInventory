import AppIntents
import SwiftData
import Foundation

/// Keep the existing intent identity so saved shortcuts continue to work.
struct LocateItem: AppIntent, CustomIntentMigratedAppIntent {
    static let intentClassName = "INLocateItem"
    static var title: LocalizedStringResource = "Find Item"
    static var description = IntentDescription("Search your inventory by name and hear matching items, their locations, and quantities.")

    @Parameter(title: "Item", requestValueDialog: "What item are you looking for?")
    var itemName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$itemName) in my inventory")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let query = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw $itemName.needsValueError("What item are you looking for?")
        }
        let coordinator = InventoryStoreCoordinator.shared
        await coordinator.refreshAccount()
        let items = try InventoryIntentSearch.matches(query, context: coordinator.container.mainContext)
        let response = items.isEmpty
            ? try InventoryIntentSearch.noMatchResponse(query, context: coordinator.container.mainContext)
            : InventoryIntentSearch.summary(items, query: query)
        return .result(value: response, dialog: IntentDialog(stringLiteral: response))
    }
}

struct ItemQuantityIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Item Quantity"
    static var description = IntentDescription("Get the total quantity of matching inventory items, including entries stored in different locations.")

    @Parameter(title: "Item", requestValueDialog: "Which item would you like to know the quantity of?")
    var itemName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get the quantity of \(\.$itemName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let query = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw $itemName.needsValueError("Which item would you like to know the quantity of?")
        }
        let coordinator = InventoryStoreCoordinator.shared
        await coordinator.refreshAccount()
        let items = try InventoryIntentSearch.matches(query, context: coordinator.container.mainContext)
        let total = items.reduce(0) { $0 + $1.quantity }
        let response = items.isEmpty
            ? try InventoryIntentSearch.noMatchResponse(query, context: coordinator.container.mainContext)
            : "The total quantity for \(query) is \(total) across \(items.count) matching inventory entries. " + InventoryIntentSearch.summary(items, query: query)
        return .result(value: total, dialog: IntentDialog(stringLiteral: response))
    }
}

/// Match exact names first so “Cable” doesn't also count “Cable organizer”.
@MainActor
enum InventoryIntentSearch {
    static func matches(_ query: String, context: ModelContext) throws -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name), SortDescriptor(\Item.itemCreationDate)]))
        let exact = items.filter { $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return exact.isEmpty ? items.filter { $0.name.localizedStandardContains(query) } : exact
    }

    // Suggestions are deliberately separate from matches: never count a guessed item.
    static func noMatchResponse(_ query: String, context: ModelContext) throws -> String {
        let names = try suggestions(query, context: context)
        let response = "I couldn't find \(query) in your inventory."
        guard !names.isEmpty else { return response }
        return response + " Similarly named items include \(names.joined(separator: ", ")). Try searching for one of those names."
    }

    static func suggestions(_ query: String, context: ModelContext) throws -> [String] {
        let query = normalized(query)
        // Very short strings produce too many unrelated guesses; bound comparison work as well.
        guard (4...80).contains(query.count) else { return [] }
        let allowance = query.count < 8 ? 1 : 2
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)]))
        var seen = Set<String>()
        var candidates: [(name: String, distance: Int)] = []
        for item in items {
            let name = normalized(item.name)
            guard seen.insert(name).inserted, name.count <= 160 else { continue }
            let words = name.split(separator: " ").map(String.init)
            let queryWordCount = query.split(separator: " ").count
            var comparisons = [name]
            if words.count >= queryWordCount {
                for start in 0...(words.count - queryWordCount) {
                    comparisons.append(words[start..<(start + queryWordCount)].joined(separator: " "))
                }
            }
            let distance = comparisons.filter { abs($0.count - query.count) <= allowance }
                .map { spellingDistance(query, $0) }.min() ?? Int.max
            if distance <= allowance { candidates.append((item.name, distance)) }
        }
        return candidates.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(3).map(\.name)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Edit distance including adjacent swapped letters (for example, “pencle”).
    private static func spellingDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        for i in 1...a.count {
            for j in 1...b.count {
                matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1,
                                   matrix[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i - 2][j - 2] + 1)
                }
            }
        }
        return matrix[a.count][b.count]
    }

    static func summary(_ items: [Item], query: String) -> String {
        guard !items.isEmpty else { return "I couldn't find \(query) in your inventory." }
        let details = items.prefix(5).map { item in
            let location = item.location?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let quantity = item.quantity == 0 ? "" : "quantity \(item.quantity), "
            return "\(item.name): \(quantity)\(location.isEmpty ? "no location set" : "at \(location)")."
        }.joined(separator: " ")
        return items.count > 5 ? details + " There are \(items.count - 5) more matching entries in the app." : details
    }
}

struct AddNewItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add New Item"
    static var description = IntentDescription("Open rInventory to create a new item.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        InventoryActionRouter.shared.requestNewItem()
        return .result()
    }
}

struct InventoryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddNewItemIntent(), phrases: [
            "Add a new item in \(.applicationName)",
            "Create an item in \(.applicationName)",
            "Add an item in \(.applicationName)"
        ], shortTitle: "Add New Item", systemImageName: "plus")
        AppShortcut(intent: LocateItem(), phrases: [
            "Find an item in \(.applicationName)",
            "Look for an item in \(.applicationName)",
            "Search in \(.applicationName)",
            "Find something in \(.applicationName)"
        ], shortTitle: "Find Item", systemImageName: "magnifyingglass")
        AppShortcut(intent: ItemQuantityIntent(), phrases: [
            "Check item quantity in \(.applicationName)",
            "Count items in \(.applicationName)"
        ], shortTitle: "Get Item Quantity", systemImageName: "number")
    }
}

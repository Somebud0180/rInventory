//
//  IntentHandler.swift
//  rInventoryIntent
//
//  Created by Ethan John Lagera on 7/31/25.
//

import Intents
import AppIntents
import os

private let logger = Logger(subsystem: "com.lagera.Inventory", category: "IntentHandler")

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        logger.debug("Received intent: \(intent)")
        
        // Check for specific intent types
        if intent is LocateItemIntent {
            return LocateItemIntentHandler()
        }
        
        logger.error("No handler for intent: \(intent)")
        return self
    }
}

// Handler for the LocateItem intent
class LocateItemIntentHandler: NSObject, LocateItemIntentHandling {
    func handle(intent: LocateItemIntent, completion: @escaping (LocateItemIntentResponse) -> Void) {
        logger.debug("Handling LocateItemIntent with item: \(intent.itemName ?? "nil")")
        
        // Create an AppIntents version of the intent and delegate to it
        let appIntent = LocateItem()
        appIntent.itemName = intent.itemName
        
        Task {
            do {
                let result = try await appIntent.perform()
                if let stringValue = result.value {
                    logger.debug("LocateItem result: \(stringValue)")
                    
                    // Parse the result string to extract item name and location
                    // Expecting format like: "ItemName is at the LocationName."
                    if let itemName = intent.itemName, stringValue.contains("is at the") {
                        let components = stringValue.components(separatedBy: " is at the ")
                        if components.count == 2 {
                            let locationName = components[1].replacingOccurrences(of: ".", with: "")
                            let response = LocateItemIntentResponse.success(itemName: itemName, locationName: locationName)
                            completion(response)
                            return
                        }
                    }
                    
                    // Fallback if we can't parse the response format
                    let response = LocateItemIntentResponse(code: .success, userActivity: nil)
                    completion(response)
                } else {
                    logger.error("Invalid result type from LocateItem.perform()")
                    let response = LocateItemIntentResponse(code: .failure, userActivity: nil)
                    completion(response)
                }
            } catch {
                logger.error("Error performing LocateItem intent: \(error.localizedDescription)")
                let response = LocateItemIntentResponse(code: .failure, userActivity: nil)
                completion(response)
            }
        }
    }
    
    // Resolve the item name parameter
    func resolveItemName(for intent: LocateItemIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let itemName = intent.itemName, !itemName.isEmpty else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        
        completion(INStringResolutionResult.success(with: itemName))
    }
}

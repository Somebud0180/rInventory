//
//  IntentHandler.swift
//  rInventoryIntent
//
//  Created by Ethan John Lagera on 7/29/25.
//
//  This file handles the intents for the app, primarily used for Siri integration.

import Intents

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        if intent is LocateItemIntent {
            return rInventoryIntentHandler()
        }
        
        fatalError("Unhandled intent type: \(intent)")
    }
}

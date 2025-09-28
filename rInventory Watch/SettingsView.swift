//
//  SettingsView.swift
//  rInventory Watch
//
//  Created by Ethan John Lagera on 9/27/25.
//

import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @EnvironmentObject var appDefaults: AppDefaults
    @Query private var items: [Item]
    
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section(header: Text("Visuals")) {
                        Toggle("Show Counter for Single Items", isOn: $appDefaults.showCounterForSingleItems)
                        // Add InventoryOptionsView from the main app here
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}

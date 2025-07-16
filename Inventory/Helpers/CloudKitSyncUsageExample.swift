//
//  CloudKitSyncUsageExample.swift
//  Inventory
//
//  Created by GitHub Copilot on 7/16/25.
//
//  Example usage of the CloudKit sync engine in your inventory app.

import SwiftUI
import SwiftData

struct CloudKitSyncUsageExample: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var syncEngine: CloudKitSyncEngine
    
    init() {
        // Initialize with a temporary context - will be updated in onAppear
        let tempContainer = try! ModelContainer(for: Item.self, Category.self, Location.self)
        self._syncEngine = StateObject(wrappedValue: CloudKitSyncEngine(modelContext: tempContainer.mainContext))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Sync Status Display
            syncStatusView
            
            // Manual Sync Controls
            syncControlsView
            
            // Last Sync Information
            lastSyncView
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Update sync engine with current model context
            syncEngine.updateModelContext(modelContext)
        }
    }
    
    private var syncStatusView: some View {
        VStack {
            Text("Sync Status")
                .font(.headline)
            
            HStack {
                Image(systemName: syncStatusIcon)
                    .foregroundColor(syncStatusColor)
                Text(syncStatusText)
                    .foregroundColor(syncStatusColor)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var syncControlsView: some View {
        VStack(spacing: 15) {
            Text("Manual Sync Controls")
                .font(.headline)
            
            HStack(spacing: 15) {
                // Full Sync Button
                Button(action: {
                    Task {
                        await syncEngine.manualSync()
                    }
                }) {
                    Label("Full Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncEngine.syncState == .syncing || !syncEngine.isAccountAvailable)
                
                // Refresh from Cloud
                Button(action: {
                    Task {
                        await syncEngine.refreshFromCloud()
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(syncEngine.syncState == .syncing || !syncEngine.isAccountAvailable)
                
                // Send to Cloud
                Button(action: {
                    Task {
                        await syncEngine.sendChangesToCloud()
                    }
                }) {
                    Label("Send", systemImage: "arrow.up.circle")
                }
                .disabled(syncEngine.syncState == .syncing || !syncEngine.isAccountAvailable)
            }
        }
    }
    
    private var lastSyncView: some View {
        VStack {
            Text("Last Sync")
                .font(.headline)
            
            if let lastSync = syncEngine.lastSyncDate {
                Text(lastSync, style: .relative)
                    .foregroundColor(.secondary)
            } else {
                Text("Never synced")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusIcon: String {
        switch syncEngine.syncState {
        case .idle:
            return syncEngine.isAccountAvailable ? "checkmark.circle" : "exclamationmark.circle"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncEngine.syncState {
        case .idle:
            return syncEngine.isAccountAvailable ? .primary : .orange
        case .syncing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var syncStatusText: String {
        switch syncEngine.syncState {
        case .idle:
            return syncEngine.isAccountAvailable ? "Ready" : "iCloud Not Available"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Sync Complete"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Integration with Existing Views

extension InventoryView {
    /// Add this as a toolbar item to show sync status
    private var syncStatusToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: {
                Task {
                    await syncEngine.manualSync()
                }
            }) {
                Label("Sync", systemImage: syncEngine.syncState == .syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .disabled(syncEngine.syncState == .syncing || !syncEngine.isAccountAvailable)
        }
    }
    
    /// Add pull-to-refresh functionality
    private var refreshableModifier: some View {
        NavigationView {
            // Your existing content
        }
        .refreshable {
            await syncEngine.refreshFromCloud()
        }
    }
}
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
    @StateObject var syncEngine: CloudKitSyncEngine
    @Query private var items: [Item]
    
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    
    private var iCloudStatusDescription: String {
        switch iCloudStatus {
        case .available: return "Active"
        case .noAccount: return "No Account"
        case .restricted: return "Restricted"
        case .couldNotDetermine: return "Could Not Determine"
        case .temporarilyUnavailable: return "Temporarily Unavailable"
        @unknown default: return "Unknown"
        }
    }
    
    private var iCloudStatusSymbol: (name: String, color: Color) {
        switch iCloudStatus {
        case .available:
            return ("checkmark.circle.fill", .green)
        case .noAccount, .restricted:
            return ("slash.circle.fill", .yellow)
        default:
            return ("minus.circle.fill", .gray)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section(header: Text("Visuals")) {
                        Toggle("Show Counter for Single Items", isOn: $appDefaults.showCounterForSingleItems)
                    }
                }
                Group {
                    Section(header: Text("iCloud Sync"), footer: Text("Sync your inventory across all devices using iCloud.")) {
                        HStack {
                            Text("iCloud Status:")
                            Spacer()
                            Image(systemName: iCloudStatusSymbol.name)
                                .foregroundColor(iCloudStatusSymbol.color)
                            Text(iCloudStatusDescription)
                                .foregroundColor(.secondary)
                        }
                        
                        if iCloudStatus == .available {
                            Button(action: {
                                Task {
                                    await syncEngine.manualSync()
                                }
                            }) {
                                HStack {
                                    Text("Sync Now")
                                    Spacer()
                                    if syncEngine.syncState == .syncing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    }
                                }
                            }.disabled(syncEngine.syncState == .syncing)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                checkiCloudAccountStatus()
            }
        }
    }
    
    private func checkiCloudAccountStatus() {
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                self.iCloudStatus = status
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    SettingsView(syncEngine: syncEngine)
}

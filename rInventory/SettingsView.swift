//
//  SettingsView.swift
//  rInventory
//
//  Created by Ethan John Lagera on 7/5/25.
//
//  A view for managing app settings.

import SwiftUI
import CloudKit
import SwiftData

let settingsActivityType = "com.lagera.Inventory.managingSettings"

struct SettingsView: View {
    @EnvironmentObject var appDefaults: AppDefaults
    
    @StateObject var syncEngine: CloudKitSyncEngine
    @State var isActive: Bool
    
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    
    private var iCloudStatusDescription: String {
        switch iCloudStatus {
        case .available: return "Available"
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
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThickMaterial)
                                .frame(width: 64, height: 64)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                        }
                        Text("Settings")
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                        Text("Customize the app and manage syncing options.")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }
                Group {
                    Section("Visuals") {
                        Toggle("Show Counter For Single Items", isOn: $appDefaults.showCounterForSingleItems)
                        Picker("Theme", selection: $appDefaults.themeMode) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
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
                        HStack {
                            Button("Sync Now") {
                                Task {
                                    await syncEngine.manualSync()
                                }
                            }
                            Spacer()
                            if syncEngine.syncState == .syncing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onAppear {
                checkiCloudAccountStatus()
            }
        }
        .userActivity(settingsActivityType, isActive: isActive) { activity in
            activity.title = "Settings"
            activity.userInfo = ["tabSelection": 1] // 1 = Settings tab
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
    @Previewable @State var isActive = true
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    SettingsView(syncEngine: syncEngine, isActive: isActive)
}

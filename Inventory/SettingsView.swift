//
//  SettingsView.swift
//  Inventory
//
//  Created by Ethan John Lagera on 7/5/25.
//
//  A view for managing app settings.

import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
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
    
    func checkiCloudAccountStatus() {
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                self.iCloudStatus = status
            }
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
                    Section("Grid View") {
                        Toggle("Show Counter For Single Items", isOn: .constant(true))
                            .disabled(true) // Placeholder for actual functionality
                    }
                }
                Group {
                    Section(header: Text("Accessibility"), footer: Text("Transitions appear when rotating the device or opening the keyboard.")) {
                        Toggle("Disable Transitions", isOn: .constant(false))
                            .disabled(true) // Placeholder for actual functionality
                        Toggle("Reduce Motion", isOn: .constant(false))
                            .disabled(true) // Placeholder for actual functionality
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
                        Button("Manually Sync") {
                            // Placeholder for manual sync action
                        }
                    }
                }
            }
            .onAppear {
                checkiCloudAccountStatus()
            }
        }
    }
}


#Preview {
    SettingsView()
}

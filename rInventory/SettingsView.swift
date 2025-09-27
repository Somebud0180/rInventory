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
import os // Add this to check for debug builds

let settingsActivityType = "com.lagera.Inventory.managingSettings"

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appDefaults: AppDefaults
    @StateObject var syncEngine: CloudKitSyncEngine
    @Query private var items: [Item]
    
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @State var isActive: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
    
    struct CreationModeOption: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let imageName: String
        let isInteractive: Bool
    }
    
    // Options for creation mode selection UI
    private let creationModeOptions = [
        CreationModeOption(title: "Interactive Item Creation", description: "Create items interactively with a guided approach.", imageName: "InteractiveView", isInteractive: true),
        CreationModeOption(title: "Form Item Creation", description: "Create items using a classic form-based approach.", imageName: "FormView", isInteractive: false)
    ]
    
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
                        LazyVGrid(
                            columns: horizontalSizeClass == .compact ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(creationModeOptions) { option in
                                SelectionCard(
                                    title: option.title,
                                    description: option.description,
                                    imageName: option.imageName,
                                    isSelected: option.isInteractive == appDefaults.useInteractiveCreation
                                ) {
                                    appDefaults.useInteractiveCreation = option.isInteractive
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text(option.title))
                                .accessibilityHint(Text(option.description))
                                .accessibilityAddTraits(option.isInteractive == appDefaults.useInteractiveCreation ? .isSelected : [])
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        
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
                        }.disabled(syncEngine.syncState == .syncing || iCloudStatus != .available)
                    }
                }
#if DEBUG
                Group {
                    Section("Debug") {
                        Button("Optimize Image Backgrounds") {
                            Task {
                                await optimizeImageBackgrounds()
                            }
                        }
                        Button("Purge Nil Location/Ghost Items") {
                            Task {
                                await purgeNilOrGhostItems()
                            }
                        }
                    }
                }
#endif // DEBUG
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
    
    // MARK: - Selection Card
    struct SelectionCard: View {
        let title: String
        let description: String
        let imageName: String
        let isSelected: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding(8)
                        .frame(height: 240)
                    
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func checkiCloudAccountStatus() {
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                self.iCloudStatus = status
            }
        }
    }
    
    private func optimizeImageBackgrounds() async {
        for item in items {
            if let imageData = item.imageData, let optimizedData = optimizePNGData(imageData) {
                await item.updateItem(
                    background: .image(optimizedData),
                    context: syncEngine.modelContext,
                    cloudKitSyncEngine: syncEngine
                )
            }
        }
    }
    
    private func purgeNilOrGhostItems() async {
        // Snapshot current items to avoid mutating while iterating the query collection
        let allItems = items
        // Define a conservative ghost heuristic
        func isGhost(_ item: Item) -> Bool {
            let nameEmpty = item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasNoVisual = item.imageData == nil && ((item.symbol ?? "").isEmpty)
            let hasNoRelations = item.location == nil && item.category == nil
            let zeroQty = item.quantity == 0
            return nameEmpty && hasNoVisual && hasNoRelations && zeroQty
        }
        
        for item in allItems {
            if isGhost(item) {
                print("Deleting item \(item.name) (ID: \(item.id))")
                await item.deleteItem(
                    context: syncEngine.modelContext,
                    cloudKitSyncEngine: syncEngine
                )
            }
        }
    }
}


#Preview {
    @Previewable @State var isActive = true
    @Previewable @StateObject var syncEngine = CloudKitSyncEngine(modelContext: ModelContext(try! ModelContainer(for: Item.self, Location.self, Category.self)))
    
    SettingsView(syncEngine: syncEngine, isActive: isActive)
}

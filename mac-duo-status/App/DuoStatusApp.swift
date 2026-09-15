//
//  DuoStatusApp.swift
//  mac-duo-status
//

import SwiftUI
import AppKit

@main
struct DuoStatusApp: App {
    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var statusStore: SystemStatusStore

    init() {
        let preferences = PreferencesStore(
            launchAtLoginManager: SystemLaunchAtLoginManager()
        )
        let status = SystemStatusStore(
            preferences: preferences,
            providers: ProviderContainer.live
        )

        _preferencesStore = StateObject(wrappedValue: preferences)
        _statusStore = StateObject(wrappedValue: status)

        status.start()
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environmentObject(statusStore)
                .environmentObject(preferencesStore)
        } label: {
            CombinedStatusIcon(
                snapshot: statusStore.snapshot,
                size: 20,
                usesColor: preferencesStore.usesColor
            )
            .contextMenu {
                settingsMenuItem

                Divider()

                Button(NSLocalizedString("common.quit", comment: "")) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(statusStore)
                .environmentObject(preferencesStore)
        }
    }

    @ViewBuilder
    private var settingsMenuItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(NSLocalizedString("settings.open", comment: ""))
            }
            .buttonStyle(ActivateApplicationBeforeActionButtonStyle())
        } else {
            Button(NSLocalizedString("settings.open", comment: "")) {
                SettingsWindowAccess.openLegacySettings()
            }
        }
    }
}

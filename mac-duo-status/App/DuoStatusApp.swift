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
    @StateObject private var controlCoordinator: ControlCoordinator

    init() {
        let preferences = PreferencesStore(
            launchAtLoginManager: SystemLaunchAtLoginManager()
        )
        let providers = ProviderContainer.live
        let status = SystemStatusStore(
            preferences: preferences,
            providers: providers
        )
        let controls = ControlCoordinator(
            statusStore: status,
            networkControl: providers.networkControl,
            powerControl: providers.powerControl
        )

        _preferencesStore = StateObject(wrappedValue: preferences)
        _statusStore = StateObject(wrappedValue: status)
        _controlCoordinator = StateObject(wrappedValue: controls)

        status.start()
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environmentObject(statusStore)
                .environmentObject(preferencesStore)
                .environmentObject(controlCoordinator)
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
                .environmentObject(controlCoordinator)
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

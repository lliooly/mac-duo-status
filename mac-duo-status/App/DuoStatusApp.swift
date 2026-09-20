//
//  DuoStatusApp.swift
//  mac-duo-status
//

import SwiftUI
import AppKit

@main
struct DuoStatusApp: App {
    @StateObject private var localizationStore: LocalizationStore
    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var statusStore: SystemStatusStore
    @StateObject private var controlCoordinator: ControlCoordinator

    init() {
        let localization = LocalizationStore()
        let preferences = PreferencesStore(
            launchAtLoginManager: SystemLaunchAtLoginManager()
        )
        let providers = ProviderContainer.live
        let widgetStatusBridge = WidgetStatusBridge()
        let status = SystemStatusStore(
            preferences: preferences,
            providers: providers,
            widgetStatusBridge: widgetStatusBridge
        )
        let controls = ControlCoordinator(
            statusStore: status,
            powerControl: providers.powerControl
        )

        _localizationStore = StateObject(wrappedValue: localization)
        _preferencesStore = StateObject(wrappedValue: preferences)
        _statusStore = StateObject(wrappedValue: status)
        _controlCoordinator = StateObject(wrappedValue: controls)

        status.start()
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView(
                batteryStatusStore: statusStore.batteryStatusStore,
                powerPolicyStatusStore: statusStore.powerPolicyStatusStore
            )
                .environmentObject(statusStore)
                .environmentObject(preferencesStore)
                .environmentObject(controlCoordinator)
                .environmentObject(localizationStore)
        } label: {
            CombinedStatusIcon(
                snapshot: statusStore.snapshot,
                size: 20,
                usesColor: preferencesStore.usesColor
            )
            .contextMenu {
                settingsMenuItem

                Divider()

                Button(localizationStore.string("common.quit")) {
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
                .environmentObject(localizationStore)
        }
    }

    @ViewBuilder
    private var settingsMenuItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(localizationStore.string("settings.open"))
            }
            .buttonStyle(ActivateApplicationBeforeActionButtonStyle())
        } else {
            Button(localizationStore.string("settings.open")) {
                SettingsWindowAccess.openLegacySettings()
            }
        }
    }
}

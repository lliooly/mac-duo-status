//
//  DuoStatusApp.swift
//  mac-duo-status
//

import SwiftUI

@main
struct DuoStatusApp: App {
    @StateObject private var localizationStore: LocalizationStore
    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var statusStore: SystemStatusStore
    @StateObject private var controlCoordinator: ControlCoordinator
    @StateObject private var statusItemController: StatusItemController

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
        _statusItemController = StateObject(
            wrappedValue: StatusItemController(
                statusStore: status,
                preferencesStore: preferences,
                controlCoordinator: controls,
                localizationStore: localization
            )
        )

        status.start()
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(statusStore)
                .environmentObject(preferencesStore)
                .environmentObject(controlCoordinator)
                .environmentObject(localizationStore)
        }
    }
}

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
                size: 22,
                usesColor: preferencesStore.usesColor
            )
            .contextMenu {
                Button(NSLocalizedString("settings.open", comment: "")) {
                    NSApplication.shared.sendAction(
                        Selector(("showSettingsWindow:")),
                        to: nil,
                        from: nil
                    )
                }

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
}

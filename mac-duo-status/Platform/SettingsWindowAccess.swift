//
//  SettingsWindowAccess.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct ActivateApplicationBeforeActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            configuration.trigger()
        } label: {
            configuration.label
        }
    }
}

@MainActor
enum SettingsWindowAccess {
    static func openLegacySettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
    }

    static func openWiFiSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let urls = [
            "x-apple.systempreferences:com.apple.wifi-settings",
            "x-apple.systempreferences:com.apple.wifi-settings-extension",
            "x-apple.systempreferences:com.apple.preference.network?Wi-Fi",
            "x-apple.systempreferences:com.apple.preference.network"
        ]

        for value in urls {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }

            return
        }
    }

    static func openBatterySettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let urls = [
            "x-apple.systempreferences:com.apple.Battery-Settings",
            "x-apple.systempreferences:com.apple.preference.battery",
            "x-apple.systempreferences:com.apple.preference.battery?Battery"
        ]

        for value in urls {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }

            return
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) {
            _ = NSWorkspace.shared.openApplication(
                at: settingsURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        _ = NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}
